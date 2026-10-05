import Foundation

/// 一度の同期の結果サマリ(UI 表示・診断用)。
public struct SyncSummary: Equatable, Sendable {
    public var pushed: Int
    public var pulled: Int
    public var deletionsPulled: Int
    /// フィールド単位LWWで「負けた」値(名刺詳細の編集履歴に出せる)。
    public var conflicts: [FieldConflict]

    public init(pushed: Int = 0, pulled: Int = 0, deletionsPulled: Int = 0, conflicts: [FieldConflict] = []) {
        self.pushed = pushed
        self.pulled = pulled
        self.deletionsPulled = deletionsPulled
        self.conflicts = conflicts
    }
}

/// レコード単位のローカルファースト同期エンジン(§5)。
///
/// `RemoteStore` プロトコルだけに依存し、Drive API を直接は呼ばない。
/// - push: dirty なカードを card.json 化してアップロード(楽観ロック If-Match)。
///   衝突したらリモートを取得→フィールド単位LWWでマージ→再アップロード。
/// - pull: 差分(初回は list=manifest 相当)を取得し、ローカルとマージして適用。
///
/// 画像バイナリ本体の転送は P2-C(Drive 実装)で追加する。本エンジンは card.json
/// (メタデータ)の収束を担う。
public final class SyncEngine: Sendable {

    private let repository: CardRepository
    private let remote: any RemoteStore
    private let imageStore: ImageStore?
    private let now: @Sendable () -> Date

    static let manifestName = "manifest.json"

    /// - Parameter imageStore: 画像バイナリの転送に使う。nil ならメタデータ(card.json)のみ同期する。
    public init(repository: CardRepository, remote: any RemoteStore,
                imageStore: ImageStore? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.repository = repository
        self.remote = remote
        self.imageStore = imageStore
        self.now = now
    }

    static func fileName(for cardId: String) -> String { "\(cardId).json" }

    /// push → pull を通しで実行する。
    @discardableResult
    public func sync() async throws -> SyncSummary {
        var summary = try await push()
        let pulled = try await pull()
        summary.pulled = pulled.pulled
        summary.deletionsPulled = pulled.deletionsPulled
        summary.conflicts += pulled.conflicts
        return summary
    }

    // MARK: - push

    @discardableResult
    public func push() async throws -> SyncSummary {
        var summary = SyncSummary()
        // 画像アップロードの重複回避用に、現在のリモートファイル名を一度だけ取得する。
        var existingNames: Set<String> = []
        if imageStore != nil {
            existingNames = Set(try await remote.list().map { $0.name })
        }
        for card in try repository.dirtyCards() {
            guard let doc = try repository.buildDocument(forCardId: card.id) else { continue }
            // card.json より先に画像本体を上げておく(受信側が参照を解決できるように)。
            try await uploadImages(doc, existing: &existingNames)
            let name = Self.fileName(for: card.id)
            let ref = try repository.remoteRef(forCardId: card.id)
            do {
                let meta = try await remote.write(name: name, data: try doc.encoded(), ifMatch: ref.remoteRevision)
                try repository.markSynced(cardId: card.id, remoteId: meta.id, remoteRevision: meta.revision, at: now())
                summary.pushed += 1
            } catch is RemoteConflictError {
                // リモートが先行 → 取得してマージし、マージ結果を現行版に対して再書き込み。
                let conflicts = try await pushWithMerge(localDoc: doc, cardId: card.id, name: name)
                summary.conflicts += conflicts
                summary.pushed += 1
            }
        }
        return summary
    }

    private func pushWithMerge(localDoc: CardDocument, cardId: String, name: String) async throws -> [FieldConflict] {
        let metas = try await remote.list()
        guard let meta = metas.first(where: { $0.name == name }) else {
            // 相手が消えた等 → 無条件で書き直す。
            let m = try await remote.write(name: name, data: try localDoc.encoded(), ifMatch: nil)
            try repository.markSynced(cardId: cardId, remoteId: m.id, remoteRevision: m.revision, at: now())
            return []
        }
        let remoteDoc = try CardDocument.decoded(try await remote.read(id: meta.id))
        let result = try LWWMerger.merge(localDoc, remoteDoc)
        // マージ結果をローカルへ反映(これから push するので未同期扱いにはしない)。
        try repository.applyRemoteDocument(result.document, remoteId: meta.id, remoteRevision: meta.revision, dirty: false)
        try repository.recordConflicts(cardId: cardId, result.conflicts)
        let written = try await remote.write(name: name, data: try result.document.encoded(), ifMatch: meta.revision)
        try repository.markSynced(cardId: cardId, remoteId: written.id, remoteRevision: written.revision, at: now())
        return result.conflicts
    }

    // MARK: - pull

    @discardableResult
    public func pull() async throws -> SyncSummary {
        var summary = SyncSummary()
        let token = try repository.syncToken()

        // 画像参照の解決(名前→メタ)用に、画像同期時は一覧を一度取得する。
        var catalog: [String: RemoteFileMeta] = [:]
        if imageStore != nil {
            catalog = Dictionary(try await remote.list().map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        }

        if let token {
            // 差分同期。
            let changes = try await remote.changes(since: token)
            for meta in changes.files {
                try await applyRemote(meta, catalog: catalog, into: &summary)
            }
            try repository.setSyncToken(changes.nextToken)
        } else {
            // 初回ブートストラップ: 先に開始トークンを確立し、その後 list(=manifest 相当)で全件取り込む。
            // 確立後に書かれたファイルは次回 pull で拾う(マージは冪等)。
            let start = try await remote.changes(since: nil)
            for meta in try await remote.list() {
                try await applyRemote(meta, catalog: catalog, into: &summary)
            }
            try repository.setSyncToken(start.nextToken)
        }
        return summary
    }

    private func applyRemote(_ meta: RemoteFileMeta, catalog: [String: RemoteFileMeta],
                             into summary: inout SyncSummary) async throws {
        // card.json のみ対象。ファイル削除(meta.deleted)は扱わない:
        // 論理削除は deleted_at 付き card.json(tombstone)として流れてくる。
        guard meta.name.hasSuffix(".json"), meta.name != Self.manifestName, !meta.deleted else { return }

        let remoteDoc = try CardDocument.decoded(try await remote.read(id: meta.id))
        let cardId = remoteDoc.id

        if let localDoc = try repository.buildDocument(forCardId: cardId) {
            let result = try LWWMerger.merge(localDoc, remoteDoc)
            // マージ結果がリモートと異なる=ローカル発の未 push 内容が残る → dirty のまま。
            let stillDirty = !Self.contentEqual(result.document, remoteDoc)
            try repository.applyRemoteDocument(result.document, remoteId: meta.id,
                                               remoteRevision: meta.revision, dirty: stillDirty)
            try repository.recordConflicts(cardId: cardId, result.conflicts)
            summary.conflicts += result.conflicts
        } else {
            try repository.applyRemoteDocument(remoteDoc, remoteId: meta.id,
                                               remoteRevision: meta.revision, dirty: false)
        }

        // 参照されている画像で、ローカルに無いものを取得する。
        try await downloadImages(remoteDoc, catalog: catalog)

        if remoteDoc.isDeleted { summary.deletionsPulled += 1 } else { summary.pulled += 1 }
    }

    // MARK: - 画像バイナリ転送(内容アドレス=sha256、不変)

    private func uploadImages(_ doc: CardDocument, existing: inout Set<String>) async throws {
        guard let imageStore else { return }
        for ref in doc.images where !existing.contains(ref.file) {
            guard imageStore.exists(relativePath: ref.file) else { continue }
            let data = try imageStore.data(forRelativePath: ref.file)
            _ = try await remote.write(name: ref.file, data: data, ifMatch: nil)
            existing.insert(ref.file)
        }
    }

    private func downloadImages(_ doc: CardDocument, catalog: [String: RemoteFileMeta]) async throws {
        guard let imageStore else { return }
        for ref in doc.images where !imageStore.exists(relativePath: ref.file) {
            guard let meta = catalog[ref.file], !meta.deleted else { continue }
            let data = try await remote.read(id: meta.id)
            try imageStore.saveRaw(data, relativePath: ref.file)
        }
    }

    /// 同期対象の内容が等価か(device_id / revision / unknown は無視)。
    static func contentEqual(_ a: CardDocument, _ b: CardDocument) -> Bool {
        a.fields == b.fields
            && a.tags == b.tags
            && Set(a.images.map { $0.sha256 }) == Set(b.images.map { $0.sha256 })
            && a.deletedAt == b.deletedAt
            && a.ocrFulltext == b.ocrFulltext
    }
}
