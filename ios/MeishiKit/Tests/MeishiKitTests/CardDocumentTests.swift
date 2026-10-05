import XCTest
@testable import MeishiKit

final class CardDocumentTests: XCTestCase {

    // 固定秒時刻(往復同値比較のため。ms精度は保持しない設計)。
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func sampleCard() -> Card {
        Card(
            id: "3f2a-uuid",
            familyName: "山田", givenName: "太郎",
            familyNameKana: "やまだ", givenNameKana: "たろう",
            company: "ABC株式会社", department: "営業部", title: "部長",
            email: "yamada@abc.co.jp",
            phone: "03-1234-5678", mobile: "090-1234-5678", fax: nil,
            postalCode: "100-0001", address: "東京都千代田区…", url: "https://abc.co.jp",
            memo: "展示会で名刺交換", isFavorite: true,
            exchangedAt: nil,
            createdAt: t0, updatedAt: t0,
            revision: 12, deviceId: "iphone-abc123", dirty: false
        )
    }

    func testCardRoundTripsThroughDocument() throws {
        let card = sampleCard()
        let doc = CardDocument(card: card, tags: ["展示会", "重要"])
        let back = doc.toCard(dirty: false)

        XCTAssertEqual(back.id, card.id)
        XCTAssertEqual(back.familyName, "山田")
        XCTAssertEqual(back.givenName, "太郎")
        XCTAssertEqual(back.company, "ABC株式会社")
        XCTAssertEqual(back.email, "yamada@abc.co.jp")
        XCTAssertEqual(back.mobile, "090-1234-5678")
        XCTAssertNil(back.fax)
        XCTAssertEqual(back.url, "https://abc.co.jp")
        XCTAssertTrue(back.isFavorite)
        XCTAssertEqual(back.revision, 12)
        XCTAssertEqual(back.deviceId, "iphone-abc123")
        // 正規化キーは同期しない(復元されない)。
        XCTAssertNil(back.companyNormalized)
        XCTAssertNil(back.emailNormalized)
    }

    func testEncodeDecodeIsStableAndFaithful() throws {
        let doc = CardDocument(card: sampleCard(), tags: ["展示会"])
        let data = try doc.encoded()
        let decoded = try CardDocument.decoded(data)

        XCTAssertEqual(decoded.id, doc.id)
        XCTAssertEqual(decoded.revision, 12)
        XCTAssertEqual(decoded.deviceId, "iphone-abc123")
        XCTAssertEqual(decoded.tags, ["展示会"])
        XCTAssertEqual(decoded.fields[CardFieldName.company]?.v, .string("ABC株式会社"))
        XCTAssertEqual(decoded.fields[CardFieldName.isFavorite]?.v, .bool(true))
        XCTAssertEqual(decoded.fields[CardFieldName.fax]?.v, .null)
        XCTAssertEqual(decoded.fields[CardFieldName.company]?.t, t0)

        // 再符号化してバイト一致(キーソートで安定していること)。
        let data2 = try decoded.encoded()
        XCTAssertEqual(data, data2)
    }

    func testJSONShapeMatchesContract() throws {
        let doc = CardDocument(card: sampleCard(), tags: ["展示会"])
        let obj = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: doc.encoded()) as? [String: Any]
        )
        XCTAssertEqual(obj["schema_version"] as? String, "1.0")
        XCTAssertEqual(obj["device_id"] as? String, "iphone-abc123")
        let fields = try XCTUnwrap(obj["fields"] as? [String: Any])
        let email = try XCTUnwrap(fields["email"] as? [String: Any])
        XCTAssertEqual(email["v"] as? String, "yamada@abc.co.jp")
        XCTAssertNotNil(email["t"] as? String)
        XCTAssertTrue(obj["deleted_at"] is NSNull)
    }

    func testUnknownTopLevelKeysRoundTrip() throws {
        // 将来バージョンが増やしたキーを含む card.json を、旧実装が失わず書き戻せること。
        let json = """
        {
          "schema_version": "1.0",
          "id": "x-1",
          "revision": 3,
          "device_id": "dev-x",
          "fields": { "company": { "v": "未来社", "t": "2026-07-19T03:12:00Z" } },
          "tags": [],
          "ocr_fulltext": null,
          "images": [],
          "created_at": "2026-07-18T10:00:00Z",
          "updated_at": "2026-07-19T03:12:00Z",
          "deleted_at": null,
          "merged_into": null,
          "future_field": { "nested": [1, true, "x"] },
          "priority": 5
        }
        """.data(using: .utf8)!

        let doc = try CardDocument.decoded(json)
        XCTAssertEqual(doc.unknown["priority"], .number(5))
        XCTAssertEqual(doc.unknown["future_field"], .object(["nested": .array([.number(1), .bool(true), .string("x")])]))

        // 書き戻すと未知キーが残っている。
        let reobj = try XCTUnwrap(try JSONSerialization.jsonObject(with: doc.encoded()) as? [String: Any])
        XCTAssertEqual(reobj["priority"] as? Int, 5)
        XCTAssertNotNil(reobj["future_field"])
    }

    func testDeletedTombstoneRoundTrips() throws {
        var card = sampleCard()
        card.deletedAt = t0
        let doc = CardDocument(card: card)
        let decoded = try CardDocument.decoded(try doc.encoded())
        XCTAssertTrue(decoded.isDeleted)
        XCTAssertEqual(decoded.deletedAt, t0)
        XCTAssertTrue(decoded.toCard().isDeleted)
    }
}
