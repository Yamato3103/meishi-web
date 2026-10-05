import Foundation

/// Card(ローカルDBモデル)⇄ CardDocument(card.json)の相互変換。
///
/// 正規化キー(companyNormalized / emailNormalized)は同期しない(§10.1)。
/// 各端末で書き込み時に再計算する。
extension CardDocument {

    /// 日付のみフィールド(exchanged_at)の UTC フォーマット(yyyy-MM-dd)。
    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Card から card.json を組み立てる。
    ///
    /// - Parameter fieldTimestamps: フィールド別の更新時刻。指定の無いフィールドは
    ///   `card.updatedAt` を用いる(Phase 2-B で DB にフィールド別時刻を持たせるまでの既定)。
    public init(card: Card, tags: [String] = [], images: [CardImage] = [],
                ocrFulltext: String? = nil, fieldTimestamps: [String: Date] = [:]) {

        func ts(_ name: String) -> Date { fieldTimestamps[name] ?? card.updatedAt }
        func s(_ name: String, _ value: String?) -> (String, CardField) {
            (name, CardField(v: value.map(JSONValue.string) ?? .null, t: ts(name)))
        }

        var f: [String: CardField] = [:]
        for (k, cardField) in [
            s(CardFieldName.familyName, card.familyName),
            s(CardFieldName.givenName, card.givenName),
            s(CardFieldName.familyNameKana, card.familyNameKana),
            s(CardFieldName.givenNameKana, card.givenNameKana),
            s(CardFieldName.company, card.company),
            s(CardFieldName.department, card.department),
            s(CardFieldName.title, card.title),
            s(CardFieldName.phone, card.phone),
            s(CardFieldName.mobile, card.mobile),
            s(CardFieldName.fax, card.fax),
            s(CardFieldName.email, card.email),
            s(CardFieldName.postalCode, card.postalCode),
            s(CardFieldName.address, card.address),
            s(CardFieldName.website, card.url),
            s(CardFieldName.memo, card.memo)
        ] {
            f[k] = cardField
        }
        f[CardFieldName.isFavorite] = CardField(v: .bool(card.isFavorite), t: ts(CardFieldName.isFavorite))
        f[CardFieldName.exchangedAt] = CardField(
            v: card.exchangedAt.map { JSONValue.string(CardDocument.dateOnly.string(from: $0)) } ?? .null,
            t: ts(CardFieldName.exchangedAt)
        )

        self.init(
            id: card.id,
            revision: card.revision,
            deviceId: card.deviceId,
            fields: f,
            tags: tags,
            ocrFulltext: ocrFulltext,
            images: images.map { ImageRef(side: $0.side.rawValue, file: $0.relativePath, sha256: $0.sha256) },
            createdAt: card.createdAt,
            updatedAt: card.updatedAt,
            deletedAt: card.deletedAt
        )
    }

    /// card.json から Card を復元する。
    ///
    /// 正規化キーは復元しない(呼び出し側=リポジトリの書き込み時に再計算)。
    /// - Parameter dirty: 取り込んだレコードを未同期扱いにするか(リモート由来なら false)。
    public func toCard(dirty: Bool = false) -> Card {
        func str(_ name: String) -> String? { fields[name]?.v.stringValue }
        let favorite = fields[CardFieldName.isFavorite]?.v.boolValue ?? false
        let exchanged = str(CardFieldName.exchangedAt).flatMap(CardDocument.dateOnly.date(from:))

        return Card(
            id: id,
            familyName: str(CardFieldName.familyName),
            givenName: str(CardFieldName.givenName),
            familyNameKana: str(CardFieldName.familyNameKana),
            givenNameKana: str(CardFieldName.givenNameKana),
            company: str(CardFieldName.company),
            companyNormalized: nil,
            department: str(CardFieldName.department),
            title: str(CardFieldName.title),
            email: str(CardFieldName.email),
            emailNormalized: nil,
            phone: str(CardFieldName.phone),
            mobile: str(CardFieldName.mobile),
            fax: str(CardFieldName.fax),
            postalCode: str(CardFieldName.postalCode),
            address: str(CardFieldName.address),
            url: str(CardFieldName.website),
            memo: str(CardFieldName.memo),
            isFavorite: favorite,
            exchangedAt: exchanged,
            createdAt: createdAt,
            updatedAt: updatedAt,
            revision: revision,
            deviceId: deviceId,
            dirty: dirty,
            deletedAt: deletedAt
        )
    }
}
