import XCTest
@testable import MeishiKit

final class LWWMergeTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ offset: TimeInterval) -> Date { base.addingTimeInterval(offset) }

    /// 指定フィールドだけ持つ最小ドキュメントを作る。
    private func doc(id: String = "card-1", revision: Int, device: String,
                     updated: Date, deleted: Date? = nil,
                     _ fields: [String: (JSONValue, Date)],
                     tags: [String] = [], images: [ImageRef] = []) -> CardDocument {
        var f: [String: CardField] = [:]
        for (k, pair) in fields { f[k] = CardField(v: pair.0, t: pair.1) }
        return CardDocument(id: id, revision: revision, deviceId: device, fields: f,
                            tags: tags, images: images,
                            createdAt: base, updatedAt: updated, deletedAt: deleted)
    }

    func testFieldLevelLWWPicksNewerPerField() throws {
        // A: company 新しい / title 古い。 B: company 古い / title 新しい。
        let a = doc(revision: 2, device: "A", updated: at(30), [
            CardFieldName.company: (.string("新A社"), at(30)),
            CardFieldName.title: (.string("旧A役職"), at(5))
        ])
        let b = doc(revision: 2, device: "B", updated: at(20), [
            CardFieldName.company: (.string("旧B社"), at(10)),
            CardFieldName.title: (.string("新B役職"), at(25))
        ])

        let result = try LWWMerger.merge(a, b)
        XCTAssertEqual(result.document.fields[CardFieldName.company]?.v, .string("新A社"))
        XCTAssertEqual(result.document.fields[CardFieldName.title]?.v, .string("新B役職"))

        // 各フィールドで「負けた」値が履歴に残る。
        let conflictFields = Set(result.conflicts.map { $0.field })
        XCTAssertEqual(conflictFields, [CardFieldName.company, CardFieldName.title])
        let companyLoss = result.conflicts.first { $0.field == CardFieldName.company }
        XCTAssertEqual(companyLoss?.losingValue, .string("旧B社"))
    }

    func testRevisionBreaksTimestampTie() throws {
        // 同時刻 → revision 大きい方を採用。
        let a = doc(revision: 5, device: "A", updated: at(10), [
            CardFieldName.email: (.string("a@x.com"), at(10))
        ])
        let b = doc(revision: 9, device: "B", updated: at(10), [
            CardFieldName.email: (.string("b@x.com"), at(10))
        ])
        let result = try LWWMerger.merge(a, b)
        XCTAssertEqual(result.document.fields[CardFieldName.email]?.v, .string("b@x.com"))
        XCTAssertEqual(result.document.revision, 9)
    }

    func testMergeIsCommutative() throws {
        let a = doc(revision: 3, device: "A", updated: at(40), [
            CardFieldName.company: (.string("A社"), at(40)),
            CardFieldName.phone: (.string("03-1"), at(5))
        ])
        let b = doc(revision: 4, device: "B", updated: at(20), [
            CardFieldName.company: (.string("B社"), at(10)),
            CardFieldName.phone: (.string("03-2"), at(30))
        ])
        let ab = try LWWMerger.merge(a, b).document
        let ba = try LWWMerger.merge(b, a).document
        XCTAssertEqual(ab.fields[CardFieldName.company]?.v, ba.fields[CardFieldName.company]?.v)
        XCTAssertEqual(ab.fields[CardFieldName.phone]?.v, ba.fields[CardFieldName.phone]?.v)
        XCTAssertEqual(ab.fields[CardFieldName.company]?.v, .string("A社"))
        XCTAssertEqual(ab.fields[CardFieldName.phone]?.v, .string("03-2"))
    }

    func testNoConflictWhenLoserIsNull() throws {
        // 片方が値、もう片方が null(未設定)。null が負けても履歴には残さない。
        let a = doc(revision: 1, device: "A", updated: at(30), [
            CardFieldName.fax: (.string("03-9"), at(30))
        ])
        let b = doc(revision: 1, device: "B", updated: at(10), [
            CardFieldName.fax: (.null, at(10))
        ])
        let result = try LWWMerger.merge(a, b)
        XCTAssertEqual(result.document.fields[CardFieldName.fax]?.v, .string("03-9"))
        XCTAssertTrue(result.conflicts.isEmpty)
    }

    func testDeletionFollowsNewerRecord() throws {
        // B の方が新しく、B が削除 → マージ結果は削除。
        let a = doc(revision: 1, device: "A", updated: at(10), [
            CardFieldName.company: (.string("生存"), at(10))
        ])
        let b = doc(revision: 2, device: "B", updated: at(50), deleted: at(50), [
            CardFieldName.company: (.string("生存"), at(10))
        ])
        let result = try LWWMerger.merge(a, b)
        XCTAssertTrue(result.document.isDeleted)
        XCTAssertEqual(result.document.deletedAt, at(50))
    }

    func testImagesUnionBySha() throws {
        let a = doc(revision: 1, device: "A", updated: at(20), [:],
                    images: [ImageRef(side: "front", file: "a_front.jpg", sha256: "sha-A")])
        let b = doc(revision: 1, device: "B", updated: at(10), [:],
                    images: [ImageRef(side: "back", file: "b_back.jpg", sha256: "sha-B")])
        let result = try LWWMerger.merge(a, b)
        XCTAssertEqual(Set(result.document.images.map { $0.sha256 }), ["sha-A", "sha-B"])
    }

    func testIdMismatchThrows() {
        let a = doc(id: "x", revision: 1, device: "A", updated: at(1), [:])
        let b = doc(id: "y", revision: 1, device: "B", updated: at(1), [:])
        XCTAssertThrowsError(try LWWMerger.merge(a, b))
    }
}
