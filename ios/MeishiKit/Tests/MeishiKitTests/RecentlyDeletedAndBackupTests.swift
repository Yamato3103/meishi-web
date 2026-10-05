import XCTest
@testable import MeishiKit

final class RecentlyDeletedAndBackupTests: XCTestCase {

    private func makeStore() throws -> ImageStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("meishi-backup-tests-\(UUID().uuidString)")
        return try ImageStore(rootDirectory: dir)
    }

    private func makeRepository(now: @escaping @Sendable () -> Date = { Date() }) throws -> CardRepository {
        let database = try AppDatabase.inMemoryMigrated()
        return CardRepository(database, deviceID: "test-device", now: now)
    }

    // MARK: - 最近削除

    func testFetchDeletedAndPermanentDelete() throws {
        let store = try makeStore()
        let repo = try makeRepository()
        let card = try repo.create(Card(familyName: "山田"))
        let saved = try store.save(Data("img".utf8), cardId: card.id, side: .front)
        _ = try repo.addImage(CardImage(cardId: card.id, relativePath: saved.relativePath, sha256: saved.sha256))

        try repo.softDelete(id: card.id)
        XCTAssertEqual(try repo.fetchDeleted().map(\.id), [card.id])
        XCTAssertTrue(try repo.fetchAll().isEmpty)

        let removedPaths = try repo.permanentlyDelete(id: card.id)
        XCTAssertEqual(removedPaths, [saved.relativePath])
        XCTAssertNil(try repo.fetchOne(id: card.id))
        XCTAssertTrue(try repo.fetchImages(cardID: card.id).isEmpty, "画像行もカスケード削除")
    }

    func testPurgeDeletedOlderThanCutoff() throws {
        let clock = MutableClock(Date(timeIntervalSince1970: 1_000_000))
        let repo = try makeRepository(now: { clock.date })

        let old = try repo.create(Card(familyName: "旧"))
        let recent = try repo.create(Card(familyName: "新"))

        clock.date = Date(timeIntervalSince1970: 1_000_000)   // 古い削除
        try repo.softDelete(id: old.id)
        clock.date = Date(timeIntervalSince1970: 2_000_000)   // 新しい削除
        try repo.softDelete(id: recent.id)

        // 1_500_000 より前に削除されたものだけパージ。
        let cutoff = Date(timeIntervalSince1970: 1_500_000)
        _ = try repo.purgeDeleted(olderThan: cutoff)

        XCTAssertNil(try repo.fetchOne(id: old.id))
        XCTAssertNotNil(try repo.fetchOne(id: recent.id))
        XCTAssertEqual(try repo.fetchDeleted().map(\.id), [recent.id])
    }

    // MARK: - バックアップ

    func testBackupExportRestoreRoundTrip() throws {
        let sourceStore = try makeStore()
        let sourceRepo = try makeRepository()

        let a = try sourceRepo.create(Card(familyName: "山田", company: "株式会社サンプル商事", email: "y@sample.co.jp"))
        let imgData = Data([0xFF, 0xD8, 0xFF, 0x01, 0x02])
        let saved = try sourceStore.save(imgData, cardId: a.id, side: .front)
        _ = try sourceRepo.addImage(CardImage(cardId: a.id, relativePath: saved.relativePath, sha256: saved.sha256, width: 100, height: 60))
        _ = try sourceRepo.create(Card(familyName: "鈴木"))

        let backup = try BackupService.export(repository: sourceRepo, imageStore: sourceStore)

        // 別の(空の)DB・画像ストアへ復元。
        let destStore = try makeStore()
        let destRepo = try makeRepository()
        let restored = try BackupService.restore(backup, into: destRepo, imageStore: destStore)

        XCTAssertEqual(restored, 2)
        let cards = try destRepo.fetchAll()
        XCTAssertEqual(Set(cards.map(\.familyName)), ["山田", "鈴木"])

        // 画像が復元され、バイト列が一致する。
        let images = try destRepo.fetchImages(cardID: a.id)
        XCTAssertEqual(images.count, 1)
        let restoredData = try destStore.data(forRelativePath: images[0].relativePath)
        XCTAssertEqual(restoredData, imgData)
        XCTAssertEqual(images[0].sha256, saved.sha256)
    }

    func testRestoreSkipsExistingIds() throws {
        let store = try makeStore()
        let repo = try makeRepository()
        let a = try repo.create(Card(familyName: "山田"))
        let backup = try BackupService.export(repository: repo, imageStore: store)

        // 同じ DB に再度復元 → 既存なのでスキップ。
        let restored = try BackupService.restore(backup, into: repo, imageStore: store)
        XCTAssertEqual(restored, 0)
        XCTAssertEqual(try repo.fetchAll().map(\.id), [a.id])
    }
}
