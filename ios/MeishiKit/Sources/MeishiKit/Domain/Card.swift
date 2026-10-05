import Foundation

/// 名刺1件。1カード = 1レコード(将来は card.json 1ファイル)に対応する。
///
/// GRDB には依存せず、純粋なドメインモデルとして定義する。
/// 永続化(テーブルマッピング)は Data 層の拡張で与える。
///
/// 同期メタ(`revision` / `deviceId` / `dirty` / `deletedAt`)は Phase 1 単体でも
/// 最初から持たせ、Phase 2 の Drive 同期で手戻りが出ないようにする。
public struct Card: Codable, Identifiable, Equatable, Hashable, Sendable {

    public var id: String

    // 氏名
    public var familyName: String?
    public var givenName: String?
    public var familyNameKana: String?
    public var givenNameKana: String?

    // 所属
    public var company: String?
    /// 重複検知用の会社突合キー(法人格除去済み)。書き込み時に自動計算。
    public var companyNormalized: String?
    public var department: String?
    public var title: String?

    // 連絡先(MVPは代表値を各1つ。複数値対応は将来拡張)
    public var email: String?
    /// 重複検知用のメール突合キー(小文字化済み)。書き込み時に自動計算。
    public var emailNormalized: String?
    public var phone: String?
    public var mobile: String?
    public var fax: String?
    public var postalCode: String?
    public var address: String?
    public var url: String?

    // 付帯情報
    public var memo: String?
    public var isFavorite: Bool
    /// 名刺交換日(任意)。
    public var exchangedAt: Date?

    // メタ
    public var createdAt: Date
    public var updatedAt: Date

    // 同期メタ
    public var revision: Int
    public var deviceId: String
    public var dirty: Bool
    /// 論理削除(tombstone)。非 nil = 削除済み。
    public var deletedAt: Date?

    public init(
        id: String = UUID().uuidString,
        familyName: String? = nil,
        givenName: String? = nil,
        familyNameKana: String? = nil,
        givenNameKana: String? = nil,
        company: String? = nil,
        companyNormalized: String? = nil,
        department: String? = nil,
        title: String? = nil,
        email: String? = nil,
        emailNormalized: String? = nil,
        phone: String? = nil,
        mobile: String? = nil,
        fax: String? = nil,
        postalCode: String? = nil,
        address: String? = nil,
        url: String? = nil,
        memo: String? = nil,
        isFavorite: Bool = false,
        exchangedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int = 0,
        deviceId: String = "",
        dirty: Bool = true,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.familyName = familyName
        self.givenName = givenName
        self.familyNameKana = familyNameKana
        self.givenNameKana = givenNameKana
        self.company = company
        self.companyNormalized = companyNormalized
        self.department = department
        self.title = title
        self.email = email
        self.emailNormalized = emailNormalized
        self.phone = phone
        self.mobile = mobile
        self.fax = fax
        self.postalCode = postalCode
        self.address = address
        self.url = url
        self.memo = memo
        self.isFavorite = isFavorite
        self.exchangedAt = exchangedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.deviceId = deviceId
        self.dirty = dirty
        self.deletedAt = deletedAt
    }

    /// 削除済みか。
    public var isDeleted: Bool { deletedAt != nil }
}
