import XCTest
@testable import MeishiKit

final class DuplicateTests: XCTestCase {

    private func makeRepository() throws -> CardRepository {
        let database = try AppDatabase.inMemoryMigrated()
        return CardRepository(database, deviceID: "test-device")
    }

    // MARK: - スコアリング

    func testScoreByEmail() {
        let a = Card(email: "Yamada@sample.co.jp")
        let b = Card(email: "yamada@sample.co.jp")
        XCTAssertEqual(DuplicateDetector.score(a, b), 60)
    }

    func testScoreByPhoneIgnoringFormat() {
        let a = Card(phone: "03-1234-5678")
        let b = Card(mobile: "0312345678")
        XCTAssertEqual(DuplicateDetector.score(a, b), 40)
    }

    func testScoreByNameAndCompany() {
        let a = Card(familyName: "山田", givenName: "太郎", company: "株式会社サンプル商事")
        let b = Card(familyName: "山田", givenName: "太郎", company: "サンプル商事")
        // 氏名一致(+30) + 会社正規化一致かつ姓一致(+20)
        XCTAssertEqual(DuplicateDetector.score(a, b), 50)
    }

    func testDifferentPeopleScoreLow() {
        let a = Card(familyName: "山田", company: "株式会社サンプル商事")
        let b = Card(familyName: "鈴木", company: "株式会社サンプル商事")
        // 同じ会社でも姓が違えば加点なし。
        XCTAssertEqual(DuplicateDetector.score(a, b), 0)
    }

    // MARK: - 検索(ブロッキング + 除外)

    func testFindDuplicatesByEmail() throws {
        let repo = try makeRepository()
        let existing = try repo.create(Card(familyName: "山田", email: "yamada@sample.co.jp"))
        let draft = Card(familyName: "山田", email: "Yamada@Sample.co.jp")

        let matches = try repo.findDuplicates(of: draft)
        XCTAssertEqual(matches.map(\.card.id), [existing.id])
        XCTAssertTrue(matches.first!.isStrong)
    }

    func testNotDuplicateExcludesPair() throws {
        let repo = try makeRepository()
        let existing = try repo.create(Card(familyName: "山田", email: "yamada@sample.co.jp"))
        var draft = Card(familyName: "山田", email: "yamada@sample.co.jp")
        // draft を実在させ、別人として記録。
        draft = try repo.create(draft)
        try repo.markNotDuplicate(existing.id, draft.id)

        let matches = try repo.findDuplicates(of: draft)
        XCTAssertTrue(matches.isEmpty, "別人確定済みは候補に出ない")
    }

    // MARK: - マージ

    func testMergeFillsBlanksMovesImageAndTombstones() throws {
        let repo = try makeRepository()
        // primary: 会社・メールあり、電話なし。secondary: 電話あり、画像あり。
        let primary = try repo.create(Card(familyName: "山田", company: "株式会社サンプル商事",
                                           email: "yamada@sample.co.jp"))
        let secondary = try repo.create(Card(familyName: "山田", phone: "03-1234-5678"))
        _ = try repo.addImage(CardImage(cardId: secondary.id, relativePath: "s.jpg", sha256: "x"))

        let merged = try repo.merge(primaryId: primary.id, secondaryId: secondary.id)

        XCTAssertEqual(merged.email, "yamada@sample.co.jp")
        XCTAssertEqual(merged.phone, "03-1234-5678", "空欄が secondary で補完される")
        XCTAssertGreaterThanOrEqual(merged.revision, 2)

        // 画像が primary に移動している。
        XCTAssertEqual(try repo.fetchImages(cardID: primary.id).count, 1)
        XCTAssertTrue(try repo.fetchImages(cardID: secondary.id).isEmpty)

        // secondary は削除済み(一覧に出ない)。
        let visibleIds = try repo.fetchAll().map(\.id)
        XCTAssertEqual(visibleIds, [primary.id])
        XCTAssertNotNil(try repo.fetchOne(id: secondary.id)?.deletedAt)
    }
}
