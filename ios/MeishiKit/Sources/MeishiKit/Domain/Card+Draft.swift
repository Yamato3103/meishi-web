import Foundation

public extension Card {

    /// 抽出結果から、確認画面の初期値となる Card ドラフトを作る。
    /// 代表値(各1つ)を採用する。ID・メタは create 時に付与されるためここでは既定のまま。
    static func draft(from result: ExtractionResult) -> Card {
        let (family, given) = splitFullName(result.personName?.full?.value)
        return Card(
            familyName: family,
            givenName: given,
            familyNameKana: result.personName?.familyKana?.value,
            givenNameKana: result.personName?.givenKana?.value,
            company: result.company?.value,
            department: result.department?.value,
            title: result.title?.value,
            email: result.email.first?.value,
            phone: result.phone.first?.value,
            mobile: result.mobile.first?.value,
            fax: result.fax.first?.value,
            postalCode: result.postalCode?.value,
            address: result.address?.value,
            url: result.url.first?.value
        )
    }

    /// フルネームを空白で姓・名に分割する。空白が無ければ全体を姓に入れる。
    static func splitFullName(_ full: String?) -> (family: String?, given: String?) {
        guard let full, !full.isEmpty else { return (nil, nil) }
        let parts = full.split(whereSeparator: { $0 == " " || $0 == "\u{3000}" }).map(String.init)
        switch parts.count {
        case 0: return (nil, nil)
        case 1: return (parts[0], nil)
        default: return (parts[0], parts[1...].joined(separator: " "))
        }
    }
}
