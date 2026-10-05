import Foundation

/// card.json のフィールド名(端末間の契約。snake_case・§10.1)。
public enum CardFieldName {
    public static let familyName = "family_name"
    public static let givenName = "given_name"
    public static let familyNameKana = "family_name_kana"
    public static let givenNameKana = "given_name_kana"
    public static let company = "company"
    public static let department = "department"
    public static let title = "title"
    public static let phone = "phone"
    public static let mobile = "mobile"
    public static let fax = "fax"
    public static let email = "email"
    public static let postalCode = "postal_code"
    public static let address = "address"
    public static let website = "website"
    public static let memo = "memo"
    public static let isFavorite = "is_favorite"
    public static let exchangedAt = "exchanged_at"

    /// Card にマッピングされる既知フィールド(順序は card.json の見た目用)。
    public static let known: [String] = [
        familyName, givenName, familyNameKana, givenNameKana,
        company, department, title,
        phone, mobile, fax, email, postalCode, address, website,
        memo, isFavorite, exchangedAt
    ]
}

/// フィールド1つ分。値 `v` と更新時刻 `t` を持つことでフィールド単位LWWが成立する(§5.3)。
public struct CardField: Equatable, Sendable {
    public var v: JSONValue
    public var t: Date

    public init(v: JSONValue, t: Date) {
        self.v = v
        self.t = t
    }
}

/// card.json に埋め込む画像参照(§10.1 の `images[]`)。
public struct ImageRef: Equatable, Sendable {
    public var side: String
    public var file: String
    public var sha256: String

    public init(side: String, file: String, sha256: String) {
        self.side = side
        self.file = file
        self.sha256 = sha256
    }
}

/// 端末間の同期単位「1名刺 = 1 JSONファイル」(§10.1)。
///
/// - 各フィールドは `{v, t}` を持ち、フィールド単位LWWで自動マージできる。
/// - `schemaVersion` と `unknown`(未知トップレベルキー)により前方互換を保つ:
///   旧バージョンアプリが新フィールドを保持したまま書き戻せる。
/// - 正規化キー(company_normalized 等)は同期しない(各端末で導出)。
public struct CardDocument: Equatable, Sendable {

    public static let currentSchemaVersion = "1.0"

    public var schemaVersion: String
    public var id: String
    public var revision: Int
    public var deviceId: String
    public var fields: [String: CardField]
    public var tags: [String]
    public var ocrFulltext: String?
    public var images: [ImageRef]
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var mergedInto: String?
    /// 未知トップレベルキー(前方互換のため素通しで保持する)。
    public var unknown: [String: JSONValue]

    public init(
        schemaVersion: String = CardDocument.currentSchemaVersion,
        id: String,
        revision: Int,
        deviceId: String,
        fields: [String: CardField],
        tags: [String] = [],
        ocrFulltext: String? = nil,
        images: [ImageRef] = [],
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        mergedInto: String? = nil,
        unknown: [String: JSONValue] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.revision = revision
        self.deviceId = deviceId
        self.fields = fields
        self.tags = tags
        self.ocrFulltext = ocrFulltext
        self.images = images
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.mergedInto = mergedInto
        self.unknown = unknown
    }

    public var isDeleted: Bool { deletedAt != nil }
}

// MARK: - エラー

public enum CardDocumentError: Error, Equatable {
    case notAnObject
    case missingField(String)
    case malformed(String)
}

// MARK: - コーデック(card.json ⇄ CardDocument)

extension CardDocument {

    /// 既知トップレベルキー。これ以外は `unknown` に退避してラウンドトリップする。
    private static let knownTopLevelKeys: Set<String> = [
        "schema_version", "id", "revision", "device_id", "fields", "tags",
        "ocr_fulltext", "images", "created_at", "updated_at", "deleted_at", "merged_into"
    ]

    /// 安定した(キー順ソート・人間可読な)card.json バイト列に符号化する。
    public func encoded() throws -> Data {
        let obj = toFoundation()
        return try JSONSerialization.data(
            withJSONObject: obj,
            options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        )
    }

    /// card.json バイト列から復元する。
    public static func decoded(_ data: Data) throws -> CardDocument {
        let any = try JSONSerialization.jsonObject(with: data)
        guard let obj = any as? [String: Any] else { throw CardDocumentError.notAnObject }
        return try CardDocument(foundation: obj)
    }

    private func toFoundation() -> [String: Any] {
        // 未知キーを先に敷き、既知キーで上書きする(前方互換のラウンドトリップ)。
        var obj: [String: Any] = unknown.mapValues { $0.toFoundation() }

        obj["schema_version"] = schemaVersion
        obj["id"] = id
        obj["revision"] = revision
        obj["device_id"] = deviceId

        var fieldsObj: [String: Any] = [:]
        for (name, field) in fields {
            fieldsObj[name] = [
                "v": field.v.toFoundation(),
                "t": ISO8601.string(from: field.t)
            ]
        }
        obj["fields"] = fieldsObj

        obj["tags"] = tags
        obj["ocr_fulltext"] = ocrFulltext ?? NSNull()
        obj["images"] = images.map { ["side": $0.side, "file": $0.file, "sha256": $0.sha256] }
        obj["created_at"] = ISO8601.string(from: createdAt)
        obj["updated_at"] = ISO8601.string(from: updatedAt)
        obj["deleted_at"] = deletedAt.map { ISO8601.string(from: $0) } ?? NSNull()
        obj["merged_into"] = mergedInto ?? NSNull()

        return obj
    }

    private init(foundation obj: [String: Any]) throws {
        func str(_ key: String) throws -> String {
            guard let s = obj[key] as? String else { throw CardDocumentError.missingField(key) }
            return s
        }
        func date(_ key: String) throws -> Date {
            let s = try str(key)
            guard let d = ISO8601.date(from: s) else { throw CardDocumentError.malformed(key) }
            return d
        }

        self.schemaVersion = (obj["schema_version"] as? String) ?? CardDocument.currentSchemaVersion
        self.id = try str("id")
        self.revision = (obj["revision"] as? NSNumber)?.intValue ?? 0
        self.deviceId = (obj["device_id"] as? String) ?? ""

        var parsedFields: [String: CardField] = [:]
        if let fieldsObj = obj["fields"] as? [String: Any] {
            for (name, raw) in fieldsObj {
                guard let entry = raw as? [String: Any] else { continue }
                let v = entry["v"].map { JSONValue(foundation: $0) } ?? .null
                let t = (entry["t"] as? String).flatMap(ISO8601.date(from:)) ?? Date(timeIntervalSince1970: 0)
                parsedFields[name] = CardField(v: v, t: t)
            }
        }
        self.fields = parsedFields

        self.tags = (obj["tags"] as? [String]) ?? []
        self.ocrFulltext = obj["ocr_fulltext"] as? String
        if let imgs = obj["images"] as? [[String: Any]] {
            self.images = imgs.compactMap { d in
                guard let side = d["side"] as? String,
                      let file = d["file"] as? String,
                      let sha = d["sha256"] as? String else { return nil }
                return ImageRef(side: side, file: file, sha256: sha)
            }
        } else {
            self.images = []
        }
        self.createdAt = try date("created_at")
        self.updatedAt = try date("updated_at")
        self.deletedAt = (obj["deleted_at"] as? String).flatMap(ISO8601.date(from:))
        self.mergedInto = obj["merged_into"] as? String

        var unknownKeys: [String: JSONValue] = [:]
        for (key, value) in obj where !CardDocument.knownTopLevelKeys.contains(key) {
            unknownKeys[key] = JSONValue(foundation: value)
        }
        self.unknown = unknownKeys
    }
}

// MARK: - ISO8601(秒精度・UTC。card.json の t / *_at 共通フォーマット)

enum ISO8601 {
    // 例に合わせ小数秒なし(2026-07-19T03:12:00Z)。ミリ秒精度は同期粒度に不要で、
    // 同時刻衝突は revision で決着する。
    // ISO8601DateFormatter は設定後の format/parse がスレッドセーフなため unsafe 指定で共有する。
    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    // 日付のみフィールド(exchanged_at 等)はローカルでは使わないが、将来の
    // 小数秒付き入力も読めるよう、パースは寛容側に倒す。
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        formatter.date(from: string) ?? fractional.date(from: string)
    }
}
