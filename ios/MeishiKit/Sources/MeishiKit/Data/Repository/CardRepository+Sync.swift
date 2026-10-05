import Foundation
import GRDB

/// 同期エンジン(`SyncEngine`)が使うリポジトリ操作。
///
/// card.json の組み立て/取り込み、フィールド別更新時刻、リモート版の突合表
/// (`card_remote`)、差分カーソル(`sync_kv`)を扱う。いずれも端末ローカルの
/// 同期台帳であり、同期対象そのものではない。
extension CardRepository {

    /// card ↔ リモートファイルの版参照(楽観ロック用)。
    public struct RemoteRef: Equatable, Sendable {
        public var remoteId: String?
        public var remoteRevision: String?
    }

    // MARK: - フィールド別更新時刻(公開読み取り)

    public func fieldTimestamps(forCardId id: String) throws -> [String: Date] {
        try database.writer.read { db in try Self.readFieldTimestamps(db, cardId: id) }
    }

    // MARK: - push 側

    /// 未同期(dirty)のカードを更新日時の昇順(古い順)で返す。tombstone も含む。
    public func dirtyCards() throws -> [Card] {
        try database.writer.read { db in
            try Card.filter(Column("dirty") == true)
                .order(Card.Columns.updatedAt)
                .fetchAll(db)
        }
    }

    /// カード1件を card.json(CardDocument)に組み立てる。tombstone も対象。
    public func buildDocument(forCardId id: String) throws -> CardDocument? {
        try database.writer.read { db in
            guard let card = try Card.fetchOne(db, key: id) else { return nil }
            let ts = try Self.readFieldTimestamps(db, cardId: id)
            let tagNames = try String.fetchAll(db, sql: """
                SELECT tags.name FROM tags
                JOIN card_tags ON card_tags.tag_id = tags.id
                WHERE card_tags.card_id = ? ORDER BY tags.name
                """, arguments: [id])
            let images = try CardImage
                .filter(CardImage.Columns.cardId == id)
                .order(CardImage.Columns.createdAt)
                .fetchAll(db)
            return CardDocument(card: card, tags: tagNames, images: images, fieldTimestamps: ts)
        }
    }

    public func remoteRef(forCardId id: String) throws -> RemoteRef {
        try database.writer.read { db in
            guard let row = try Row.fetchOne(db,
                sql: "SELECT remote_id, remote_revision FROM card_remote WHERE card_id = ?",
                arguments: [id]) else { return RemoteRef() }
            return RemoteRef(remoteId: row["remote_id"], remoteRevision: row["remote_revision"])
        }
    }

    /// push 成功を記録する。リモート版を保存し、dirty を落とす。
    public func markSynced(cardId: String, remoteId: String?, remoteRevision: String, at when: Date) throws {
        try database.writer.write { db in
            try Self.upsertRemote(db, cardId: cardId, remoteId: remoteId, remoteRevision: remoteRevision, at: when)
            try db.execute(sql: "UPDATE cards SET dirty = 0 WHERE id = ?", arguments: [cardId])
        }
    }

    // MARK: - pull 側

    /// リモート由来の card.json をローカルへ適用する(挿入/更新)。revision は doc の値をそのまま採用し、
    /// 通常の書き込み経路(revision++/正規化以外)を通さない=マージ結果を忠実に格納する。
    /// - Parameter dirty: ローカルに未 push の内容が残るなら true。
    public func applyRemoteDocument(_ doc: CardDocument, remoteId: String?, remoteRevision: String?, dirty: Bool) throws {
        var card = doc.toCard(dirty: dirty)
        // 正規化キーは同期しないため各端末で再計算する。
        card.emailNormalized = Normalizer.email(card.email)
        card.companyNormalized = Normalizer.companyKey(card.company)

        try database.writer.write { db in
            let exists = try Card.fetchOne(db, key: card.id) != nil
            if exists { try card.update(db) } else { try card.insert(db) }

            // フィールド別時刻を doc の t から反映。
            var ts: [String: Date] = [:]
            for name in CardFieldName.known {
                if let t = doc.fields[name]?.t { ts[name] = t }
            }
            try Self.writeFieldTimestamps(db, cardId: card.id, ts)

            // タグを doc.tags に合わせて置き換える(名前で解決/作成)。
            try Self.replaceTags(db, cardId: card.id, names: doc.tags, now: now())

            // 画像の DB 行を doc.images に合わせる(バイナリ本体は SyncEngine が別途転送)。
            try Self.replaceImages(db, cardId: card.id, refs: doc.images, now: now())

            if let remoteRevision {
                try Self.upsertRemote(db, cardId: card.id, remoteId: remoteId,
                                      remoteRevision: remoteRevision, at: now())
            }
        }
    }

    // MARK: - 競合履歴(field_conflicts)

    /// マージで負けた値を履歴として記録する。
    public func recordConflicts(cardId: String, _ conflicts: [FieldConflict]) throws {
        guard !conflicts.isEmpty else { return }
        let t = now()
        try database.writer.write { db in
            for c in conflicts {
                let record = FieldConflictRecord(
                    cardId: cardId, field: c.field,
                    losingValue: c.losingValue.displayText,
                    winningValue: c.winningValue.displayText,
                    losingAt: c.losingTimestamp, winningAt: c.winningTimestamp,
                    createdAt: t)
                try record.insert(db)
            }
        }
    }

    /// カードの競合履歴(新しい順)。
    public func conflicts(forCardId id: String) throws -> [FieldConflictRecord] {
        try database.writer.read { db in
            try FieldConflictRecord
                .filter(FieldConflictRecord.Columns.cardId == id)
                .order(FieldConflictRecord.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    /// 競合履歴を1件破棄する。
    public func dismissConflict(id: String) throws {
        try database.writer.write { db in
            _ = try FieldConflictRecord.deleteOne(db, key: id)
        }
    }

    /// カードの競合履歴をすべて破棄する。
    public func dismissConflicts(forCardId id: String) throws {
        try database.writer.write { db in
            _ = try FieldConflictRecord
                .filter(FieldConflictRecord.Columns.cardId == id)
                .deleteAll(db)
        }
    }

    // MARK: - 同期カーソル(sync_kv)

    private static let tokenKey = "changes_token"

    public func syncToken() throws -> String? {
        try database.writer.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM sync_kv WHERE key = ?", arguments: [Self.tokenKey])
        }
    }

    public func setSyncToken(_ token: String) throws {
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO sync_kv (key, value) VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """, arguments: [Self.tokenKey, token])
        }
    }

    // MARK: - 内部(生SQL)

    private static func upsertRemote(_ db: Database, cardId: String, remoteId: String?,
                                     remoteRevision: String, at when: Date) throws {
        try db.execute(sql: """
            INSERT INTO card_remote (card_id, remote_id, remote_revision, synced_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(card_id) DO UPDATE SET
                remote_id = excluded.remote_id,
                remote_revision = excluded.remote_revision,
                synced_at = excluded.synced_at
            """, arguments: [cardId, remoteId, remoteRevision, when])
    }

    /// card_tags を names 集合に一致させる(名前で既存タグ解決、無ければ作成)。
    static func replaceTags(_ db: Database, cardId: String, names: [String], now: Date) throws {
        try db.execute(sql: "DELETE FROM card_tags WHERE card_id = ?", arguments: [cardId])
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let normalized = Normalizer.nfkc(trimmed).lowercased()
            var tagId = try String.fetchOne(db,
                sql: "SELECT id FROM tags WHERE name_normalized = ?", arguments: [normalized])
            if tagId == nil {
                let newId = UUID().uuidString
                try db.execute(
                    sql: "INSERT INTO tags (id, name, name_normalized, created_at) VALUES (?, ?, ?, ?)",
                    arguments: [newId, trimmed, normalized, now])
                tagId = newId
            }
            try db.execute(
                sql: "INSERT OR IGNORE INTO card_tags (card_id, tag_id) VALUES (?, ?)",
                arguments: [cardId, tagId])
        }
    }

    /// card_images を doc の参照集合に一致させる(relativePath をキーに差分適用)。
    static func replaceImages(_ db: Database, cardId: String, refs: [ImageRef], now: Date) throws {
        let existing = try CardImage.filter(CardImage.Columns.cardId == cardId).fetchAll(db)
        let wantedPaths = Set(refs.map { $0.file })
        for row in existing where !wantedPaths.contains(row.relativePath) {
            _ = try CardImage.deleteOne(db, key: row.id)
        }
        let existingPaths = Set(existing.map { $0.relativePath })
        for ref in refs where !existingPaths.contains(ref.file) {
            let side = CardImage.Side(rawValue: ref.side) ?? .front
            let image = CardImage(cardId: cardId, side: side, relativePath: ref.file,
                                  sha256: ref.sha256, createdAt: now)
            try image.insert(db)
        }
    }
}
