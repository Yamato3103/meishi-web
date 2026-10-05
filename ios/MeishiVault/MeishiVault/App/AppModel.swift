import Foundation
import UIKit
import MeishiKit

/// アプリ全体の状態と、MeishiKit(DB / 画像ストア / リポジトリ)への入口。
///
/// M1-C の縦串: 取り込み → 画像保存(sha256)→ Card 作成 → 一覧更新 を担う。
@MainActor
@Observable
final class AppModel {

    let repository: CardRepository
    let imageStore: ImageStore
    let sync: SyncController

    private(set) var cards: [Card] = []

    init() {
        let support = URL.applicationSupportDirectory.appending(path: "MeishiVault")
        let dbURL = support.appending(path: "meishi.sqlite")
        let imagesDir = support.appending(path: "CardImages")

        // 起動に失敗した場合はアプリとして機能しないため、ここでは致命エラーとして扱う。
        // (M1-C の範囲。将来は初期化失敗のリカバリ UI を検討)
        do {
            let database = try AppDatabase.open(at: dbURL)
            let imageStore = try ImageStore(rootDirectory: imagesDir)
            let repository = CardRepository(database, deviceID: AppModel.resolveDeviceId())
            self.imageStore = imageStore
            self.repository = repository
            self.sync = SyncController(repository: repository, imageStore: imageStore)
        } catch {
            fatalError("データベース初期化に失敗: \(error)")
        }

        purgeExpiredDeleted()
        reload()

        #if DEBUG
        // 検証用: 起動引数 --demo-import があり、まだ空なら合成名刺を1件取り込む。
        if ProcessInfo.processInfo.arguments.contains("--demo-import"), cards.isEmpty {
            DemoImport.run(using: self)
        }
        // 検証用: --demo-conflict で、先頭カードに競合履歴を1件仕込む(詳細UIの確認用)。
        if ProcessInfo.processInfo.arguments.contains("--demo-conflict"), let first = cards.first {
            try? repository.recordConflicts(cardId: first.id, [
                FieldConflict(
                    field: CardFieldName.company,
                    losingValue: .string("株式会社サンプル(旧社名)"),
                    losingTimestamp: Date().addingTimeInterval(-3600),
                    winningValue: .string("株式会社サンプル商事"),
                    winningTimestamp: Date()
                )
            ])
        }
        // 検証用: --demo-sync でフォルダ同期を有効化し、一度同期する。
        if ProcessInfo.processInfo.arguments.contains("--demo-sync") {
            sync.setEnabled(true)
            Task { [weak self] in
                _ = await self?.sync.syncNow()
                self?.reload()
            }
        }
        #endif
    }

    /// 最近削除の保持期間(確定#3: 30日)。
    private let recentlyDeletedRetentionDays = 30

    /// 一覧を DB から読み直す。
    func reload() {
        cards = (try? repository.fetchAll()) ?? []
    }

    /// 検索結果(空クエリなら全件)。
    func search(_ query: String) -> [Card] {
        (try? repository.search(query)) ?? []
    }

    /// カードの内容を更新して一覧を更新する。
    func update(_ card: Card) {
        _ = try? repository.update(card)
        reload()
    }

    /// 論理削除(最近削除へ)。
    func delete(_ card: Card) {
        try? repository.softDelete(id: card.id)
        reload()
    }

    /// お気に入りの切り替え。
    func toggleFavorite(_ card: Card) {
        var updated = card
        updated.isFavorite.toggle()
        update(updated)
    }

    /// 最新の1件を取得(詳細画面が編集後に再読込するため)。
    func card(id: String) -> Card? {
        try? repository.fetchOne(id: id)
    }

    /// ドラフトの重複候補(スコア降順)。
    func findDuplicates(of draft: Card) -> [DuplicateMatch] {
        (try? repository.findDuplicates(of: draft)) ?? []
    }

    /// primary を残し secondary を統合(空欄補完・画像移動・secondary は削除)。
    @discardableResult
    func merge(keeping primary: Card, removing secondary: Card) -> Card? {
        let merged = try? repository.merge(primaryId: primary.id, secondaryId: secondary.id)
        reload()
        return merged
    }

    /// 「別人」として記録する。
    func markNotDuplicate(_ a: Card, _ b: Card) {
        try? repository.markNotDuplicate(a.id, b.id)
    }

    // MARK: - 最近削除

    /// 最近削除の一覧(削除日時の新しい順)。
    func recentlyDeleted() -> [Card] {
        (try? repository.fetchDeleted()) ?? []
    }

    /// 復元する。
    func restore(_ card: Card) {
        try? repository.restore(id: card.id)
        reload()
    }

    /// 完全削除(DB行 + 画像ファイル)。
    func permanentlyDelete(_ card: Card) {
        let paths = (try? repository.permanentlyDelete(id: card.id)) ?? []
        paths.forEach { try? imageStore.delete(relativePath: $0) }
        reload()
    }

    /// 保持期間を過ぎた最近削除を自動パージする(起動時)。
    private func purgeExpiredDeleted() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -recentlyDeletedRetentionDays, to: Date()) ?? Date()
        let paths = (try? repository.purgeDeleted(olderThan: cutoff)) ?? []
        paths.forEach { try? imageStore.delete(relativePath: $0) }
    }

    // MARK: - タグ

    func allTags() -> [Tag] {
        (try? repository.allTags()) ?? []
    }

    func tags(for card: Card) -> [Tag] {
        (try? repository.tags(forCardId: card.id)) ?? []
    }

    /// 名前からタグを作成/取得して、カードに付与する。
    func addTag(named name: String, to card: Card) {
        guard let tag = try? repository.createOrGetTag(name: name) else { return }
        try? repository.addTag(tag.id, toCardId: card.id)
    }

    func setTag(_ tag: Tag, on card: Card, isOn: Bool) {
        if isOn {
            try? repository.addTag(tag.id, toCardId: card.id)
        } else {
            try? repository.removeTag(tag.id, fromCardId: card.id)
        }
    }

    func cardIds(withTag tag: Tag) -> Set<String> {
        (try? repository.cardIds(withTagId: tag.id)) ?? []
    }

    func deleteTag(_ tag: Tag) {
        try? repository.deleteTag(id: tag.id)
    }

    // MARK: - 同期の競合履歴

    /// カードの競合履歴(自動解決で負けた値)。
    func conflicts(for card: Card) -> [FieldConflictRecord] {
        (try? repository.conflicts(forCardId: card.id)) ?? []
    }

    func dismissConflict(_ record: FieldConflictRecord) {
        try? repository.dismissConflict(id: record.id)
    }

    func dismissAllConflicts(for card: Card) {
        try? repository.dismissConflicts(forCardId: card.id)
    }

    // MARK: - バックアップ

    /// 全データをバックアップファイル(.json)に書き出し、共有用 URL を返す。
    func exportBackupFile() -> URL? {
        guard let data = try? BackupService.export(repository: repository, imageStore: imageStore) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MeishiVault-backup.json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// バックアップファイルから復元する(新規のみ)。
    /// - Returns: 復元件数。
    @discardableResult
    func importBackup(from url: URL) -> Int {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return 0 }
        let count = (try? BackupService.restore(data, into: repository, imageStore: imageStore)) ?? 0
        reload()
        return count
    }

    /// 取り込み確定: 補正済み画像を保存し、Card と CardImage を作成する。
    /// - Parameter draft: 確認画面で編集済みの内容(ID・メタは create 時に付与)。
    /// - Returns: 作成した Card。
    @discardableResult
    func importCard(
        processed: ImagePipeline.Processed,
        draft: Card
    ) throws -> Card {
        let card = try repository.create(draft)
        let saved = try imageStore.save(processed.jpegData, cardId: card.id, side: .front)
        try repository.addImage(
            CardImage(
                cardId: card.id,
                side: .front,
                relativePath: saved.relativePath,
                sha256: saved.sha256,
                width: processed.width,
                height: processed.height
            )
        )
        reload()
        return card
    }

    /// カードの代表画像(表)を UIImage で読み出す。一覧のサムネイル用。
    func frontImage(for card: Card) -> UIImage? {
        guard
            let image = (try? repository.fetchImages(cardID: card.id))?.first,
            let data = try? imageStore.data(forRelativePath: image.relativePath)
        else { return nil }
        return UIImage(data: data)
    }

    /// この端末の識別子(同期の由来端末)。初回に生成して UserDefaults に保存。
    private static func resolveDeviceId() -> String {
        let key = "meishivault.device_id"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }
}
