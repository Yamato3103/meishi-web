import XCTest
@testable import MeishiKit

final class TagTests: XCTestCase {

    private func makeRepository() throws -> CardRepository {
        let database = try AppDatabase.inMemoryMigrated()
        return CardRepository(database, deviceID: "test-device")
    }

    func testCreateOrGetDedupesByNormalizedName() throws {
        let repo = try makeRepository()
        let a = try repo.createOrGetTag(name: "  取引先 ")
        let b = try repo.createOrGetTag(name: "取引先")
        XCTAssertEqual(a.id, b.id, "正規化一致は同じタグ")
        XCTAssertEqual(try repo.allTags().count, 1)
    }

    func testAssignAndFetchTagsForCard() throws {
        let repo = try makeRepository()
        let card = try repo.create(Card(familyName: "山田"))
        let t1 = try repo.createOrGetTag(name: "取引先")
        let t2 = try repo.createOrGetTag(name: "重要")

        try repo.addTag(t1.id, toCardId: card.id)
        try repo.addTag(t2.id, toCardId: card.id)
        try repo.addTag(t1.id, toCardId: card.id) // 重複は無視

        // 名前順(Unicode コードポイント順で 取引先 < 重要)。
        XCTAssertEqual(try repo.tags(forCardId: card.id).map(\.name), ["取引先", "重要"])
    }

    func testCardIdsWithTagAndRemove() throws {
        let repo = try makeRepository()
        let a = try repo.create(Card(familyName: "山田"))
        let b = try repo.create(Card(familyName: "鈴木"))
        let tag = try repo.createOrGetTag(name: "取引先")
        try repo.addTag(tag.id, toCardId: a.id)
        try repo.addTag(tag.id, toCardId: b.id)

        XCTAssertEqual(try repo.cardIds(withTagId: tag.id), [a.id, b.id])

        try repo.removeTag(tag.id, fromCardId: b.id)
        XCTAssertEqual(try repo.cardIds(withTagId: tag.id), [a.id])
    }

    func testDeletingCardCascadesCardTags() throws {
        let repo = try makeRepository()
        let card = try repo.create(Card(familyName: "山田"))
        let tag = try repo.createOrGetTag(name: "取引先")
        try repo.addTag(tag.id, toCardId: card.id)

        _ = try repo.permanentlyDelete(id: card.id)
        XCTAssertTrue(try repo.cardIds(withTagId: tag.id).isEmpty)
        XCTAssertEqual(try repo.allTags().count, 1, "タグ自体は残る")
    }

    func testDeleteTagRemovesAssignments() throws {
        let repo = try makeRepository()
        let card = try repo.create(Card(familyName: "山田"))
        let tag = try repo.createOrGetTag(name: "取引先")
        try repo.addTag(tag.id, toCardId: card.id)

        try repo.deleteTag(id: tag.id)
        XCTAssertTrue(try repo.allTags().isEmpty)
        XCTAssertTrue(try repo.tags(forCardId: card.id).isEmpty)
    }
}
