import XCTest
@testable import MeishiKit

final class VCardTests: XCTestCase {

    func testBuildsCoreFields() {
        let card = Card(
            familyName: "山田", givenName: "太郎",
            familyNameKana: "やまだ", givenNameKana: "たろう",
            company: "株式会社サンプル商事", department: "営業部", title: "課長",
            email: "yamada@sample.co.jp", phone: "03-1234-5678", mobile: "090-1234-5678",
            fax: "03-1234-5679", postalCode: "100-0001", address: "東京都千代田区丸の内1-2-3",
            url: "https://sample.co.jp"
        )
        let vcard = VCardBuilder.build(card)

        XCTAssertTrue(vcard.hasPrefix("BEGIN:VCARD\r\nVERSION:3.0"))
        XCTAssertTrue(vcard.hasSuffix("END:VCARD"))
        XCTAssertTrue(vcard.contains("N:山田;太郎;;;"))
        XCTAssertTrue(vcard.contains("FN:山田 太郎"))
        XCTAssertTrue(vcard.contains("ORG:株式会社サンプル商事;営業部"))
        XCTAssertTrue(vcard.contains("TITLE:課長"))
        XCTAssertTrue(vcard.contains("EMAIL;TYPE=INTERNET,WORK:yamada@sample.co.jp"))
        XCTAssertTrue(vcard.contains("TEL;TYPE=WORK,VOICE:03-1234-5678"))
        XCTAssertTrue(vcard.contains("TEL;TYPE=CELL,VOICE:090-1234-5678"))
        XCTAssertTrue(vcard.contains("TEL;TYPE=WORK,FAX:03-1234-5679"))
        XCTAssertTrue(vcard.contains("X-PHONETIC-LAST-NAME:やまだ"))
        XCTAssertTrue(vcard.contains("URL:https://sample.co.jp"))
    }

    func testEscapesSpecialCharacters() {
        let card = Card(company: "サンプル; 商事, 株式会社")
        let vcard = VCardBuilder.build(card)
        // ; と , はエスケープされる。
        XCTAssertTrue(vcard.contains("ORG:サンプル\\; 商事\\, 株式会社;"))
    }

    func testFallsBackToCompanyWhenNoName() {
        let card = Card(company: "株式会社サンプル商事")
        XCTAssertTrue(VCardBuilder.build(card).contains("FN:株式会社サンプル商事"))
    }

    func testBuildsMultipleCards() {
        let cards = [Card(familyName: "山田"), Card(familyName: "鈴木")]
        let vcard = VCardBuilder.build(cards: cards)
        XCTAssertEqual(vcard.components(separatedBy: "BEGIN:VCARD").count - 1, 2)
        XCTAssertTrue(vcard.hasSuffix("\r\n"))
    }

    func testEmbedsPhoto() {
        let card = Card(familyName: "山田")
        let vcard = VCardBuilder.build(card, photoJPEG: Data([0xFF, 0xD8, 0xFF]))
        XCTAssertTrue(vcard.contains("PHOTO;ENCODING=b;TYPE=JPEG:/9j/"))
    }
}
