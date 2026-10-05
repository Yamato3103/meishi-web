import Foundation

/// Card から vCard(バージョン 3.0)テキストを生成する。
///
/// 3.0 は連絡先アプリや各種サービスとの互換性が高い。UIKit には依存しないため
/// macOS でもテストでき、画像は任意で JPEG を渡すと PHOTO として埋め込む。
public enum VCardBuilder {

    /// 単一カードの vCard 文字列(末尾に改行は付けない)。
    public static func build(_ card: Card, photoJPEG: Data? = nil) -> String {
        var lines: [String] = ["BEGIN:VCARD", "VERSION:3.0"]

        // N: 姓;名;ミドル;敬称;接尾
        let n = [card.familyName ?? "", card.givenName ?? "", "", "", ""]
            .map(escape).joined(separator: ";")
        lines.append("N:" + n)
        lines.append("FN:" + escape(fullName(card)))

        // ふりがな(3.0 の非標準拡張だが Apple 連絡先が解釈する)
        if let kana = nonEmpty(card.familyNameKana) {
            lines.append("X-PHONETIC-LAST-NAME:" + escape(kana))
        }
        if let kana = nonEmpty(card.givenNameKana) {
            lines.append("X-PHONETIC-FIRST-NAME:" + escape(kana))
        }

        if nonEmpty(card.company) != nil || nonEmpty(card.department) != nil {
            let org = [card.company ?? "", card.department ?? ""].map(escape).joined(separator: ";")
            lines.append("ORG:" + org)
        }
        if let title = nonEmpty(card.title) { lines.append("TITLE:" + escape(title)) }
        if let email = nonEmpty(card.email) { lines.append("EMAIL;TYPE=INTERNET,WORK:" + escape(email)) }
        if let phone = nonEmpty(card.phone) { lines.append("TEL;TYPE=WORK,VOICE:" + escape(phone)) }
        if let mobile = nonEmpty(card.mobile) { lines.append("TEL;TYPE=CELL,VOICE:" + escape(mobile)) }
        if let fax = nonEmpty(card.fax) { lines.append("TEL;TYPE=WORK,FAX:" + escape(fax)) }

        if nonEmpty(card.address) != nil || nonEmpty(card.postalCode) != nil {
            // po;ext;street;locality;region;postal;country
            let adr = ["", "", card.address ?? "", "", "", card.postalCode ?? "", ""]
                .map(escape).joined(separator: ";")
            lines.append("ADR;TYPE=WORK:" + adr)
        }
        if let url = nonEmpty(card.url) { lines.append("URL:" + escape(url)) }
        if let memo = nonEmpty(card.memo) { lines.append("NOTE:" + escape(memo)) }
        if let photo = photoJPEG {
            lines.append("PHOTO;ENCODING=b;TYPE=JPEG:" + photo.base64EncodedString())
        }

        lines.append("END:VCARD")
        return lines.joined(separator: "\r\n")
    }

    /// 複数カードを連結した vCard(各カードの後に CRLF)。
    public static func build(cards: [Card]) -> String {
        cards.map { build($0) }.joined(separator: "\r\n") + "\r\n"
    }

    // MARK: - ヘルパー

    public static func fullName(_ card: Card) -> String {
        let name = [card.familyName, card.givenName].compactMap { $0 }.joined(separator: " ")
        if !name.isEmpty { return name }
        return nonEmpty(card.company) ?? "名称未設定"
    }

    /// vCard のテキスト値エスケープ(\ , ; 改行)。
    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
