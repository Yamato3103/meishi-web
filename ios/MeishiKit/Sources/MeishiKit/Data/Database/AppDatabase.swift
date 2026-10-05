import Foundation
import GRDB

/// アプリのデータベースアクセスの入口。
///
/// GRDB の `DatabaseWriter`(`DatabaseQueue` / `DatabasePool`)を包み、
/// マイグレーションやリポジトリはこの型を経由して DB にアクセスする。
/// M1-A ではまだスキーマを持たず、接続の疎通だけを担保する。
/// スキーマ(cards など)は M1-B のマイグレーションで追加する。
public struct AppDatabase: Sendable {

    /// 読み書きに使う GRDB のライター(GRDB の `DatabaseWriter` は Sendable)。
    public let writer: any DatabaseWriter

    /// 既存のライターを包んで初期化する。
    /// - Parameter writer: `DatabaseQueue` などの `DatabaseWriter`。
    public init(_ writer: any DatabaseWriter) {
        self.writer = writer
    }

    /// テスト・プレビュー用のインメモリ DB を生成する(マイグレーション未適用)。
    ///
    /// ディスクに触れないため高速で、CI でも安定して動く。
    public static func inMemory() throws -> AppDatabase {
        let dbQueue = try DatabaseQueue()
        return AppDatabase(dbQueue)
    }

    /// マイグレーション適用済みのインメモリ DB(リポジトリのテスト用)。
    public static func inMemoryMigrated() throws -> AppDatabase {
        let database = try inMemory()
        try database.migrate()
        return database
    }

    /// 指定パスにオンディスク DB を開き、マイグレーションを適用して返す。
    /// アプリ本体はこれを使って永続化する。
    public static func open(at url: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let dbQueue = try DatabaseQueue(path: url.path)
        let database = AppDatabase(dbQueue)
        try database.migrate()
        return database
    }

    /// 登録済みマイグレーションを適用する。冪等(再実行しても安全)。
    public func migrate() throws {
        try Self.migrator.migrate(writer)
    }

    /// スキーマ定義。マイグレーションは常に追記のみ(既存の書き換え禁止)。
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_cards_and_images") { db in
            try db.create(table: "cards") { t in
                t.primaryKey("id", .text)

                // 氏名
                t.column("family_name", .text)
                t.column("given_name", .text)
                t.column("family_name_kana", .text)
                t.column("given_name_kana", .text)

                // 所属
                t.column("company", .text)
                t.column("company_normalized", .text)
                t.column("department", .text)
                t.column("title", .text)

                // 連絡先
                t.column("email", .text)
                t.column("email_normalized", .text)
                t.column("phone", .text)
                t.column("mobile", .text)
                t.column("fax", .text)
                t.column("postal_code", .text)
                t.column("address", .text)
                t.column("url", .text)

                // 付帯情報
                t.column("memo", .text)
                t.column("is_favorite", .boolean).notNull().defaults(to: false)
                t.column("exchanged_at", .datetime)

                // メタ
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()

                // 同期メタ
                t.column("revision", .integer).notNull().defaults(to: 0)
                t.column("device_id", .text).notNull().defaults(to: "")
                t.column("dirty", .boolean).notNull().defaults(to: true)
                t.column("deleted_at", .datetime)
            }
            try db.create(index: "idx_cards_updated_at", on: "cards", columns: ["updated_at"])
            try db.create(index: "idx_cards_deleted_at", on: "cards", columns: ["deleted_at"])
            try db.create(index: "idx_cards_email_normalized", on: "cards", columns: ["email_normalized"])
            try db.create(index: "idx_cards_company_normalized", on: "cards", columns: ["company_normalized"])

            try db.create(table: "card_images") { t in
                t.primaryKey("id", .text)
                t.column("card_id", .text)
                    .notNull()
                    .references("cards", onDelete: .cascade)
                t.column("side", .text).notNull()
                t.column("relative_path", .text).notNull()
                t.column("sha256", .text).notNull()
                t.column("width", .integer)
                t.column("height", .integer)
                t.column("created_at", .datetime).notNull()
            }
            try db.create(index: "idx_card_images_card_id", on: "card_images", columns: ["card_id"])
            try db.create(index: "idx_card_images_sha256", on: "card_images", columns: ["sha256"])
        }

        migrator.registerMigration("v2_cards_fts5") { db in
            // 全文検索(FTS5)。日本語の部分一致のため trigram トークナイザを使う
            // (形態素解析なしで「山田」「やまだ」等の部分一致が効く)。
            // cards を外部コンテンツ(content='cards')にして重複保存を避け、
            // トリガで INSERT/UPDATE/DELETE を同期する。設計書 §4.3 準拠。
            try db.execute(sql: """
                CREATE VIRTUAL TABLE cards_fts USING fts5(
                    family_name, given_name, family_name_kana, given_name_kana,
                    company, department, title, email, address, memo,
                    content='cards', content_rowid='rowid', tokenize='trigram'
                );
                """)

            // 既存行を投入(移行時に空でも安全)。
            try db.execute(sql: """
                INSERT INTO cards_fts(
                    rowid, family_name, given_name, family_name_kana, given_name_kana,
                    company, department, title, email, address, memo)
                SELECT rowid, family_name, given_name, family_name_kana, given_name_kana,
                    company, department, title, email, address, memo
                FROM cards;
                """)

            try db.execute(sql: """
                CREATE TRIGGER cards_fts_ai AFTER INSERT ON cards BEGIN
                    INSERT INTO cards_fts(
                        rowid, family_name, given_name, family_name_kana, given_name_kana,
                        company, department, title, email, address, memo)
                    VALUES (new.rowid, new.family_name, new.given_name, new.family_name_kana, new.given_name_kana,
                        new.company, new.department, new.title, new.email, new.address, new.memo);
                END;
                """)

            try db.execute(sql: """
                CREATE TRIGGER cards_fts_ad AFTER DELETE ON cards BEGIN
                    INSERT INTO cards_fts(
                        cards_fts, rowid, family_name, given_name, family_name_kana, given_name_kana,
                        company, department, title, email, address, memo)
                    VALUES ('delete', old.rowid, old.family_name, old.given_name, old.family_name_kana, old.given_name_kana,
                        old.company, old.department, old.title, old.email, old.address, old.memo);
                END;
                """)

            try db.execute(sql: """
                CREATE TRIGGER cards_fts_au AFTER UPDATE ON cards BEGIN
                    INSERT INTO cards_fts(
                        cards_fts, rowid, family_name, given_name, family_name_kana, given_name_kana,
                        company, department, title, email, address, memo)
                    VALUES ('delete', old.rowid, old.family_name, old.given_name, old.family_name_kana, old.given_name_kana,
                        old.company, old.department, old.title, old.email, old.address, old.memo);
                    INSERT INTO cards_fts(
                        rowid, family_name, given_name, family_name_kana, given_name_kana,
                        company, department, title, email, address, memo)
                    VALUES (new.rowid, new.family_name, new.given_name, new.family_name_kana, new.given_name_kana,
                        new.company, new.department, new.title, new.email, new.address, new.memo);
                END;
                """)
        }

        migrator.registerMigration("v3_not_duplicate_pairs") { db in
            // 「別人」と確定したペアを記録し、次回以降サジェストしない(設計書 §8)。
            // card_id_a < card_id_b の正準順で1行に正規化する。
            try db.create(table: "not_duplicate_pairs") { t in
                t.column("card_id_a", .text).notNull()
                t.column("card_id_b", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.primaryKey(["card_id_a", "card_id_b"])
            }
        }

        migrator.registerMigration("v4_tags") { db in
            try db.create(table: "tags") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("name_normalized", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.uniqueKey(["name_normalized"])
            }
            try db.create(table: "card_tags") { t in
                t.column("card_id", .text).notNull().references("cards", onDelete: .cascade)
                t.column("tag_id", .text).notNull().references("tags", onDelete: .cascade)
                t.primaryKey(["card_id", "tag_id"])
            }
            try db.create(index: "idx_card_tags_tag_id", on: "card_tags", columns: ["tag_id"])
        }

        migrator.registerMigration("v5_sync_field_timestamps") { db in
            // フィールド単位LWW(§5.3)のため、各フィールドの最終更新時刻を保持する。
            // Card モデルには載せず(tags の name_normalized と同様)、Data 層が生SQLで管理する。
            // 値は JSON マップ {"family_name":"2026-...Z", ...}。
            try db.alter(table: "cards") { t in
                t.add(column: "field_updated_at", .text)
            }

            // 同期カーソル等の Key-Value(例: Drive changes の pageToken)。
            try db.create(table: "sync_kv") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }

            // 端末ローカルのリモート対応表(card ↔ リモートファイルの版)。
            // 楽観ロック(If-Match 相当)と差分適用の突合に使う。同期しない端末固有情報。
            try db.create(table: "card_remote") { t in
                t.primaryKey("card_id", .text).references("cards", onDelete: .cascade)
                t.column("remote_id", .text)
                t.column("remote_revision", .text)
                t.column("synced_at", .datetime)
            }
        }

        migrator.registerMigration("v6_field_conflicts") { db in
            // 同期のフィールド単位LWWで負けた値の履歴(§5.3)。カード削除でカスケード。
            try db.create(table: "field_conflicts") { t in
                t.primaryKey("id", .text)
                t.column("card_id", .text).notNull().references("cards", onDelete: .cascade)
                t.column("field", .text).notNull()
                t.column("losing_value", .text)
                t.column("winning_value", .text)
                t.column("losing_at", .datetime).notNull()
                t.column("winning_at", .datetime).notNull()
                t.column("created_at", .datetime).notNull()
            }
            try db.create(index: "idx_field_conflicts_card_id", on: "field_conflicts", columns: ["card_id"])
        }

        return migrator
    }
}
