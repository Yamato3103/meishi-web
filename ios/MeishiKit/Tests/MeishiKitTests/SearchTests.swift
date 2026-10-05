import XCTest
@testable import MeishiKit

final class SearchTests: XCTestCase {

    private func makeRepository() throws -> CardRepository {
        let database = try AppDatabase.inMemoryMigrated()
        return CardRepository(database, deviceID: "test-device")
    }

    func testFtsFindsByKanaAndCompany() throws {
        let repo = try makeRepository()
        _ = try repo.create(Card(familyName: "山田", givenName: "太郎",
                                 familyNameKana: "やまだ", company: "株式会社サンプル商事"))
        _ = try repo.create(Card(familyName: "鈴木", givenName: "花子",
                                 familyNameKana: "すずき", company: "テスト工業"))

        XCTAssertEqual(try repo.search("やまだ").map(\.familyName), ["山田"])
        XCTAssertEqual(try repo.search("サンプル").map(\.familyName), ["山田"])
        XCTAssertEqual(try repo.search("テスト").map(\.familyName), ["鈴木"])
    }

    func testShortQueryUsesLikeFallback() throws {
        let repo = try makeRepository()
        _ = try repo.create(Card(familyName: "山田", company: "サンプル商事"))
        _ = try repo.create(Card(familyName: "山本", company: "別会社"))

        // 1文字(trigram不可)→ LIKE フォールバックで両方ヒット。
        XCTAssertEqual(Set(try repo.search("山").map(\.familyName)), ["山田", "山本"])
        // 会社名の一部でも 1〜2 文字は LIKE。
        XCTAssertEqual(try repo.search("別").map(\.familyName), ["山本"])
    }

    func testSearchExcludesDeleted() throws {
        let repo = try makeRepository()
        let a = try repo.create(Card(familyName: "山田", company: "株式会社サンプル商事"))
        try repo.softDelete(id: a.id)

        XCTAssertTrue(try repo.search("サンプル").isEmpty)
        XCTAssertTrue(try repo.search("山").isEmpty)
    }

    func testUpdatedContentIsSearchable() throws {
        let repo = try makeRepository()
        var card = try repo.create(Card(familyName: "山田", company: "旧社名工業"))

        // 会社名を更新 → 新しい語で検索でき、古い語では出ない。
        card.company = "新会社ホールディングス"
        _ = try repo.update(card)

        XCTAssertEqual(try repo.search("ホールディングス").map(\.familyName), ["山田"])
        XCTAssertTrue(try repo.search("旧社名").isEmpty)
    }

    func testEmptyQueryReturnsAll() throws {
        let repo = try makeRepository()
        _ = try repo.create(Card(familyName: "山田"))
        _ = try repo.create(Card(familyName: "鈴木"))
        XCTAssertEqual(try repo.search("   ").count, 2)
    }
}
