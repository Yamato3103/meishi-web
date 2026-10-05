import Foundation
import GRDB

// ドメインモデルに GRDB の永続化能力を「拡張」で付与する。
// Domain 層は GRDB を知らず、テーブルマッピングはこの Data 層に閉じ込める。
//
// Swift プロパティ(camelCase)⇔ DB カラム(snake_case)の変換は
// convert(From/To)SnakeCase 戦略に任せる(例: familyNameKana ⇔ family_name_kana)。

extension Card: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "cards"
    public static let databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy = .convertFromSnakeCase
    public static let databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy = .convertToSnakeCase

    /// 型安全にカラムを参照するための定義(リポジトリのクエリで使用)。
    public enum Columns {
        public static let id = Column("id")
        public static let updatedAt = Column("updated_at")
        public static let deletedAt = Column("deleted_at")
        public static let isFavorite = Column("is_favorite")
    }
}

extension CardImage: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "card_images"
    public static let databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy = .convertFromSnakeCase
    public static let databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy = .convertToSnakeCase

    public enum Columns {
        public static let cardId = Column("card_id")
        public static let createdAt = Column("created_at")
        public static let sha256 = Column("sha256")
    }
}

extension FieldConflictRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "field_conflicts"
    public static let databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy = .convertFromSnakeCase
    public static let databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy = .convertToSnakeCase

    public enum Columns {
        public static let cardId = Column("card_id")
        public static let createdAt = Column("created_at")
    }
}

// Tag は name_normalized 列(モデルに無い NOT NULL 列)を持つため、
// 挿入はリポジトリの生 SQL で行う。ここでは取得(Fetch)とクエリのみ対応する。
extension Tag: FetchableRecord, TableRecord {
    public static let databaseTableName = "tags"
    public static let databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy = .convertFromSnakeCase

    public enum Columns {
        public static let name = Column("name")
        public static let nameNormalized = Column("name_normalized")
    }
}
