import Foundation
import GRDB

/// 名刺の永続化ユースケース。
///
/// 書き込み時に「revision++ / dirty=1 / updated_at 更新 / 正規化カラム再計算 / device_id 付与」を
/// 必ず一括で通す。これにより Phase 2 の同期メタが常に整合する。
public struct CardRepository: Sendable {

    let database: AppDatabase
    private let deviceID: String
    let now: @Sendable () -> Date

    /// - Parameters:
    ///   - database: マイグレーション適用済みの `AppDatabase`。
    ///   - deviceID: この端末の識別子(同期の由来端末)。
    ///   - now: 現在時刻の供給。テストで固定するため注入可能にしている。
    public init(_ database: AppDatabase, deviceID: String, now: @escaping @Sendable () -> Date = { Date() }) {
        self.database = database
        self.deviceID = deviceID
        self.now = now
    }

    // MARK: - 書き込み

    /// 新規作成。createdAt/updatedAt を現在時刻に、revision を 1 にする。
    @discardableResult
    public func create(_ card: Card) throws -> Card {
        var c = card
        let t = now()
        c.createdAt = t
        c.updatedAt = t
        c.revision = 1
        c.dirty = true
        c.deviceId = deviceID
        c.deletedAt = nil
        applyNormalization(&c)
        try database.writer.write { db in
            try c.insert(db)
            // 新規は全フィールドを作成時刻で stamp する。
            let ts = Self.computedFieldTimestamps(new: c, old: nil, existing: [:], at: t)
            try Self.writeFieldTimestamps(db, cardId: c.id, ts)
        }
        return c
    }

    /// 既存カードの更新。revision を +1 し、updatedAt を現在時刻にする。
    @discardableResult
    public func update(_ card: Card) throws -> Card {
        var c = card
        let t = now()
        c.updatedAt = t
        c.revision += 1
        c.dirty = true
        c.deviceId = deviceID
        applyNormalization(&c)
        try database.writer.write { db in
            let old = try Card.fetchOne(db, key: c.id)
            let existing = try Self.readFieldTimestamps(db, cardId: c.id)
            try c.update(db)
            let ts = Self.computedFieldTimestamps(new: c, old: old, existing: existing, at: t)
            try Self.writeFieldTimestamps(db, cardId: c.id, ts)
        }
        return c
    }

    /// 論理削除(tombstone)。deleted_at を立て、同期メタを更新する。
    public func softDelete(id: String) throws {
        try mutate(id: id) { c, t in
            c.deletedAt = t
        }
    }

    /// 論理削除の取り消し(最近削除からの復元)。
    public func restore(id: String) throws {
        try mutate(id: id) { c, _ in
            c.deletedAt = nil
        }
    }

    // MARK: - 読み取り

    /// カード一覧。既定では削除済みを除外し、更新日時の降順で返す。
    public func fetchAll(includeDeleted: Bool = false) throws -> [Card] {
        try database.writer.read { db in
            var request = Card.all()
            if !includeDeleted {
                request = request.filter(Card.Columns.deletedAt == nil)
            }
            return try request.order(Card.Columns.updatedAt.desc).fetchAll(db)
        }
    }

    public func fetchOne(id: String) throws -> Card? {
        try database.writer.read { db in
            try Card.fetchOne(db, key: id)
        }
    }

    /// 最近削除(論理削除済み)を、削除日時の新しい順で返す。
    public func fetchDeleted() throws -> [Card] {
        try database.writer.read { db in
            try Card
                .filter(Card.Columns.deletedAt != nil)
                .order(Card.Columns.deletedAt.desc)
                .fetchAll(db)
        }
    }

    /// 物理削除(完全削除)。card_images 行は FK カスケードで消えるため、
    /// 呼び出し側がファイルを消せるよう画像の相対パスを返す。
    @discardableResult
    public func permanentlyDelete(id: String) throws -> [String] {
        try database.writer.write { db in
            let paths = try CardImage
                .filter(CardImage.Columns.cardId == id)
                .fetchAll(db)
                .map(\.relativePath)
            _ = try Card.deleteOne(db, key: id)
            return paths
        }
    }

    /// 指定日時より前に削除されたカードを完全削除する(自動パージ)。
    /// - Returns: 消したファイルの相対パス一覧。
    @discardableResult
    public func purgeDeleted(olderThan cutoff: Date) throws -> [String] {
        try database.writer.write { db in
            let expired = try Card
                .filter(Card.Columns.deletedAt != nil && Card.Columns.deletedAt < cutoff)
                .fetchAll(db)
            var paths: [String] = []
            for card in expired {
                paths += try CardImage
                    .filter(CardImage.Columns.cardId == card.id)
                    .fetchAll(db)
                    .map(\.relativePath)
                _ = try Card.deleteOne(db, key: card.id)
            }
            return paths
        }
    }

    /// 全文検索。削除済みは除外し、更新日時の降順で返す。
    /// 3文字以上は FTS5(trigram)、それ未満は trigram が索引を作れないため LIKE で代替する。
    public func search(_ query: String) throws -> [Card] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return try fetchAll() }

        return try database.writer.read { db in
            if trimmed.count < 3 {
                let like = "%\(Self.escapeLike(trimmed))%"
                let sql = """
                    SELECT cards.* FROM cards
                    WHERE cards.deleted_at IS NULL AND (
                        family_name LIKE ? ESCAPE '\\' OR given_name LIKE ? ESCAPE '\\'
                        OR family_name_kana LIKE ? ESCAPE '\\' OR given_name_kana LIKE ? ESCAPE '\\'
                        OR company LIKE ? ESCAPE '\\' OR email LIKE ? ESCAPE '\\'
                    )
                    ORDER BY cards.updated_at DESC
                    """
                let args = StatementArguments(Array(repeating: like, count: 6))
                return try Card.fetchAll(db, sql: sql, arguments: args)
            } else {
                // フレーズ("..."）として渡し、trigram で部分一致させる。二重引用符はエスケープ。
                let phrase = "\"" + trimmed.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                let sql = """
                    SELECT cards.* FROM cards
                    JOIN cards_fts ON cards_fts.rowid = cards.rowid
                    WHERE cards_fts MATCH ? AND cards.deleted_at IS NULL
                    ORDER BY cards.updated_at DESC
                    """
                return try Card.fetchAll(db, sql: sql, arguments: [phrase])
            }
        }
    }

    /// LIKE のワイルドカード(% _ \)をエスケープする。
    private static func escapeLike(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    // MARK: - 重複検知

    /// ドラフト(新規/編集中カード)に対する重複候補を、スコア降順で返す。
    /// ブロッキング: email_normalized / company_normalized / 電話文字列で候補を絞り、
    /// not_duplicate で「別人」確定済みのペアは除外する。
    public func findDuplicates(of draft: Card) throws -> [DuplicateMatch] {
        try database.writer.read { db in
            let emailKey = Normalizer.email(draft.email)
            let companyKey = Normalizer.companyKey(draft.company)
            let phones = [draft.phone, draft.mobile, draft.fax].compactMap { $0 }.filter { !$0.isEmpty }

            var clauses: [String] = []
            var args: [DatabaseValueConvertible] = []
            if let emailKey { clauses.append("email_normalized = ?"); args.append(emailKey) }
            if let companyKey { clauses.append("company_normalized = ?"); args.append(companyKey) }
            for phone in phones {
                clauses.append("phone = ?"); args.append(phone)
                clauses.append("mobile = ?"); args.append(phone)
                clauses.append("fax = ?"); args.append(phone)
            }
            guard !clauses.isEmpty else { return [] }

            let sql = """
                SELECT * FROM cards
                WHERE deleted_at IS NULL AND id <> ? AND (\(clauses.joined(separator: " OR ")))
                """
            let candidates = try Card.fetchAll(db, sql: sql, arguments: StatementArguments([draft.id] + args))

            var matches: [DuplicateMatch] = []
            for candidate in candidates {
                if try Self.isNotDuplicate(db, draft.id, candidate.id) { continue }
                let score = DuplicateDetector.score(draft, candidate)
                if score >= DuplicateDetector.candidateThreshold {
                    matches.append(DuplicateMatch(card: candidate, score: score))
                }
            }
            return matches.sorted { $0.score > $1.score }
        }
    }

    /// 2枚を1枚に統合する。primary を残し、空欄を secondary で補完、
    /// secondary の画像を primary に付け替え、secondary は tombstone にする。
    @discardableResult
    public func merge(primaryId: String, secondaryId: String) throws -> Card {
        try database.writer.write { db in
            guard
                let primaryOriginal = try Card.fetchOne(db, key: primaryId),
                var secondary = try Card.fetchOne(db, key: secondaryId)
            else {
                throw DatabaseError(message: "merge: カードが見つかりません")
            }

            var primary = DuplicateDetector.merged(primary: primaryOriginal, secondary: secondary)
            let t = now()
            primary.updatedAt = t
            primary.revision += 1
            primary.dirty = true
            primary.deviceId = deviceID
            applyNormalization(&primary)
            try primary.update(db)
            let existingTs = try Self.readFieldTimestamps(db, cardId: primaryId)
            let ts = Self.computedFieldTimestamps(new: primary, old: primaryOriginal, existing: existingTs, at: t)
            try Self.writeFieldTimestamps(db, cardId: primaryId, ts)

            // 画像を primary へ付け替え(ファイルはそのまま、card_id のみ更新)。
            try db.execute(sql: "UPDATE card_images SET card_id = ? WHERE card_id = ?",
                           arguments: [primaryId, secondaryId])

            // secondary を tombstone。
            secondary.deletedAt = t
            secondary.updatedAt = t
            secondary.revision += 1
            secondary.dirty = true
            secondary.deviceId = deviceID
            try secondary.update(db)

            return primary
        }
    }

    /// 「別人」確定を記録する(正準順で保存)。
    public func markNotDuplicate(_ idA: String, _ idB: String) throws {
        let (a, b) = Self.canonicalPair(idA, idB)
        try database.writer.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO not_duplicate_pairs (card_id_a, card_id_b, created_at) VALUES (?, ?, ?)",
                arguments: [a, b, now()]
            )
        }
    }

    private static func isNotDuplicate(_ db: Database, _ idA: String, _ idB: String) throws -> Bool {
        let (a, b) = canonicalPair(idA, idB)
        return try Bool.fetchOne(db,
            sql: "SELECT EXISTS(SELECT 1 FROM not_duplicate_pairs WHERE card_id_a = ? AND card_id_b = ?)",
            arguments: [a, b]) ?? false
    }

    private static func canonicalPair(_ idA: String, _ idB: String) -> (String, String) {
        idA < idB ? (idA, idB) : (idB, idA)
    }

    // MARK: - 画像

    @discardableResult
    public func addImage(_ image: CardImage) throws -> CardImage {
        try database.writer.write { db in try image.insert(db) }
        return image
    }

    public func fetchImages(cardID: String) throws -> [CardImage] {
        try database.writer.read { db in
            try CardImage
                .filter(CardImage.Columns.cardId == cardID)
                .order(CardImage.Columns.createdAt)
                .fetchAll(db)
        }
    }

    // MARK: - タグ

    /// 全タグ(名前順)。
    public func allTags() throws -> [Tag] {
        try database.writer.read { db in
            try Tag.order(Tag.Columns.name).fetchAll(db)
        }
    }

    /// カードに付いているタグ(名前順)。
    public func tags(forCardId cardId: String) throws -> [Tag] {
        try database.writer.read { db in
            try Tag.fetchAll(db, sql: """
                SELECT tags.* FROM tags
                JOIN card_tags ON card_tags.tag_id = tags.id
                WHERE card_tags.card_id = ?
                ORDER BY tags.name
                """, arguments: [cardId])
        }
    }

    /// 同名(正規化一致)のタグがあれば返し、無ければ作成する。
    @discardableResult
    public func createOrGetTag(name: String) throws -> Tag {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = Normalizer.nfkc(trimmed).lowercased()
        return try database.writer.write { db in
            if let existing = try Tag.fetchOne(db,
                sql: "SELECT * FROM tags WHERE name_normalized = ?", arguments: [normalized]) {
                return existing
            }
            let tag = Tag(name: trimmed)
            try db.execute(
                sql: "INSERT INTO tags (id, name, name_normalized, created_at) VALUES (?, ?, ?, ?)",
                arguments: [tag.id, tag.name, normalized, tag.createdAt]
            )
            return tag
        }
    }

    public func addTag(_ tagId: String, toCardId cardId: String) throws {
        try database.writer.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO card_tags (card_id, tag_id) VALUES (?, ?)",
                arguments: [cardId, tagId]
            )
            // タグ集合の変更を同期に載せるため、カードを未同期(dirty)にして版を進める。
            try touchCard(db, id: cardId)
        }
    }

    public func removeTag(_ tagId: String, fromCardId cardId: String) throws {
        try database.writer.write { db in
            try db.execute(
                sql: "DELETE FROM card_tags WHERE card_id = ? AND tag_id = ?",
                arguments: [cardId, tagId]
            )
            try touchCard(db, id: cardId)
        }
    }

    /// カードの同期メタだけを進める(値は変えずに dirty/updated_at/revision を更新)。
    /// タグ集合など「フィールド以外」の変更を同期へ載せるために使う。
    private func touchCard(_ db: Database, id: String) throws {
        try db.execute(sql: """
            UPDATE cards SET dirty = 1, revision = revision + 1, updated_at = ?, device_id = ?
            WHERE id = ?
            """, arguments: [now(), deviceID, id])
    }

    /// 指定タグが付いたカードの id 集合(一覧の絞り込み用)。
    public func cardIds(withTagId tagId: String) throws -> Set<String> {
        try database.writer.read { db in
            let ids = try String.fetchAll(db,
                sql: "SELECT card_id FROM card_tags WHERE tag_id = ?", arguments: [tagId])
            return Set(ids)
        }
    }

    /// タグを削除する(card_tags は FK カスケードで消える)。
    public func deleteTag(id: String) throws {
        try database.writer.write { db in
            // カスケードで外れるカードを、削除の同期反映のため先に touch しておく。
            let affected = try String.fetchAll(db,
                sql: "SELECT card_id FROM card_tags WHERE tag_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM tags WHERE id = ?", arguments: [id])
            for cardId in affected { try touchCard(db, id: cardId) }
        }
    }

    // MARK: - 内部

    /// id で1件取得し、変更を適用してから同期メタを更新して保存する共通処理。
    private func mutate(id: String, _ change: (inout Card, _ now: Date) -> Void) throws {
        try database.writer.write { db in
            guard var c = try Card.fetchOne(db, key: id) else { return }
            let old = c
            let existing = try Self.readFieldTimestamps(db, cardId: id)
            let t = now()
            change(&c, t)
            c.updatedAt = t
            c.revision += 1
            c.dirty = true
            c.deviceId = deviceID
            applyNormalization(&c)
            try c.update(db)
            let ts = Self.computedFieldTimestamps(new: c, old: old, existing: existing, at: t)
            try Self.writeFieldTimestamps(db, cardId: id, ts)
        }
    }

    private func applyNormalization(_ c: inout Card) {
        c.emailNormalized = Normalizer.email(c.email)
        c.companyNormalized = Normalizer.companyKey(c.company)
    }

    // MARK: - フィールド別更新時刻(field_updated_at 列。フィールド単位LWWの土台)

    /// 変更のあったフィールドの時刻だけを `t` に更新する(値が変わらなければ据え置き)。
    /// 新規(old=nil)は全既知フィールドを `t`(=createdAt)にする。
    static func computedFieldTimestamps(new: Card, old: Card?, existing: [String: Date], at t: Date) -> [String: Date] {
        let newFields = CardDocument(card: new).fields
        let oldFields = old.map { CardDocument(card: $0).fields }
        var result = existing
        for name in CardFieldName.known {
            let nv = newFields[name]?.v ?? .null
            if let oldFields {
                let ov = oldFields[name]?.v ?? .null
                if ov != nv { result[name] = t }
                else if result[name] == nil { result[name] = t }
            } else {
                result[name] = t
            }
        }
        return result
    }

    static func writeFieldTimestamps(_ db: Database, cardId: String, _ map: [String: Date]) throws {
        let obj = map.mapValues { ISO8601.string(from: $0) }
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        try db.execute(sql: "UPDATE cards SET field_updated_at = ? WHERE id = ?",
                       arguments: [String(decoding: data, as: UTF8.self), cardId])
    }

    static func readFieldTimestamps(_ db: Database, cardId: String) throws -> [String: Date] {
        guard
            let json = try String.fetchOne(db, sql: "SELECT field_updated_at FROM cards WHERE id = ?", arguments: [cardId]),
            let data = json.data(using: .utf8),
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        return obj.compactMapValues { ISO8601.date(from: $0) }
    }
}
