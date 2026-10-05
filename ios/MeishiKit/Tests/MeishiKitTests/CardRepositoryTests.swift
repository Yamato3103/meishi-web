import XCTest
import GRDB
@testable import MeishiKit

final class CardRepositoryTests: XCTestCase {

    private func makeRepository(now: @escaping @Sendable () -> Date = { Date() }) throws -> CardRepository {
        let database = try AppDatabase.inMemoryMigrated()
        return CardRepository(database, deviceID: "test-device", now: now)
    }

    func testMigrationIsIdempotent() throws {
        let database = try AppDatabase.inMemoryMigrated()
        // 2回目のマイグレーションでも例外を投げない。
        XCTAssertNoThrow(try database.migrate())
    }

    func testCreateStampsMetadataAndNormalization() throws {
        // DB は日時をミリ秒精度で保存するため、往復同値比較には丸め誤差の出ない
        // 固定時刻(秒ちょうど)を使う。
        let repo = try makeRepository(now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let created = try repo.create(
            Card(familyName: "山田", givenName: "太郎",
                 company: "株式会社サンプル商事",
                 email: "Yamada@Sample.co.jp")
        )

        XCTAssertEqual(created.revision, 1)
        XCTAssertTrue(created.dirty)
        XCTAssertEqual(created.deviceId, "test-device")
        XCTAssertEqual(created.emailNormalized, "yamada@sample.co.jp")
        XCTAssertEqual(created.companyNormalized, "サンプル商事")
        XCTAssertNil(created.deletedAt)

        let fetched = try repo.fetchOne(id: created.id)
        XCTAssertEqual(fetched, created)
    }

    func testFetchAllExcludesDeletedAndOrdersByUpdatedAtDesc() throws {
        let clock = MutableClock(Date(timeIntervalSince1970: 1_000_000))
        let repo = try makeRepository(now: { clock.date })

        clock.date = Date(timeIntervalSince1970: 1_000_000)
        let a = try repo.create(Card(familyName: "A"))
        clock.date = Date(timeIntervalSince1970: 1_000_100)
        let b = try repo.create(Card(familyName: "B"))

        let all = try repo.fetchAll()
        XCTAssertEqual(all.map(\.id), [b.id, a.id], "更新日時の降順で並ぶ")

        try repo.softDelete(id: b.id)
        let visible = try repo.fetchAll()
        XCTAssertEqual(visible.map(\.id), [a.id], "削除済みは既定で除外")

        let includingDeleted = try repo.fetchAll(includeDeleted: true)
        XCTAssertEqual(Set(includingDeleted.map(\.id)), Set([a.id, b.id]))
    }

    func testUpdateBumpsRevisionAndUpdatedAt() throws {
        let clock = MutableClock(Date(timeIntervalSince1970: 2_000_000))
        let repo = try makeRepository(now: { clock.date })

        var card = try repo.create(Card(familyName: "田中", company: "有限会社テスト"))
        XCTAssertEqual(card.revision, 1)

        clock.date = Date(timeIntervalSince1970: 2_000_050)
        card.company = "テスト工業株式会社"
        let updated = try repo.update(card)

        XCTAssertEqual(updated.revision, 2)
        XCTAssertEqual(updated.updatedAt, Date(timeIntervalSince1970: 2_000_050))
        XCTAssertEqual(updated.companyNormalized, "テスト工業")
    }

    func testSoftDeleteAndRestore() throws {
        let repo = try makeRepository()
        let card = try repo.create(Card(familyName: "削除太郎"))

        try repo.softDelete(id: card.id)
        let deleted = try repo.fetchOne(id: card.id)
        XCTAssertNotNil(deleted?.deletedAt)
        XCTAssertEqual(deleted?.revision, 2)

        try repo.restore(id: card.id)
        let restored = try repo.fetchOne(id: card.id)
        XCTAssertNil(restored?.deletedAt)
        XCTAssertEqual(restored?.revision, 3)
    }

    func testAddImageAndFetch() throws {
        let repo = try makeRepository()
        let card = try repo.create(Card(familyName: "画像太郎"))

        let image = try repo.addImage(
            CardImage(cardId: card.id, side: .front,
                      relativePath: "images/\(card.id)-front.jpg",
                      sha256: "abc123", width: 1024, height: 640,
                      createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        )

        let images = try repo.fetchImages(cardID: card.id)
        XCTAssertEqual(images, [image])
        XCTAssertEqual(images.first?.side, .front)
        XCTAssertEqual(images.first?.sha256, "abc123")
    }

    func testImageCascadesOnCardHardDelete() throws {
        let database = try AppDatabase.inMemoryMigrated()
        let repo = CardRepository(database, deviceID: "test-device")
        let card = try repo.create(Card(familyName: "連鎖太郎"))
        _ = try repo.addImage(
            CardImage(cardId: card.id, relativePath: "p.jpg", sha256: "x")
        )

        // 物理削除すると外部キーの ON DELETE CASCADE で画像も消える。
        try database.writer.write { db in
            _ = try Card.deleteOne(db, key: card.id)
        }

        let images = try repo.fetchImages(cardID: card.id)
        XCTAssertTrue(images.isEmpty)
    }
}
