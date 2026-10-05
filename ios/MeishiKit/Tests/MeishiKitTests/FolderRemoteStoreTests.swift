import XCTest
@testable import MeishiKit

final class FolderRemoteStoreTests: XCTestCase {

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MeishiFolderStore-\(UUID().uuidString)", isDirectory: true)
    }

    func testPersistsAcrossInstances() async throws {
        let dir = tempDir()
        let s1 = try FolderRemoteStore(root: dir)
        let meta = try await s1.write(name: "a.json", data: Data("hi".utf8), ifMatch: nil)

        // 別インスタンス(=アプリ再起動相当)で索引とバイト列が復元される。
        let s2 = try FolderRemoteStore(root: dir)
        let listed = try await s2.list()
        XCTAssertEqual(listed.map(\.name), ["a.json"])
        let data = try await s2.read(id: meta.id)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "hi")
    }

    func testOptimisticLockAndChanges() async throws {
        let store = try FolderRemoteStore(root: tempDir())
        let v1 = try await store.write(name: "c.json", data: Data("1".utf8), ifMatch: nil)
        let bootstrap = try await store.changes(since: nil)

        _ = try await store.write(name: "c.json", data: Data("2".utf8), ifMatch: v1.revision)
        do {
            _ = try await store.write(name: "c.json", data: Data("3".utf8), ifMatch: v1.revision)
            XCTFail("stale write should conflict")
        } catch is RemoteConflictError { /* expected */ }

        let delta = try await store.changes(since: bootstrap.nextToken)
        XCTAssertEqual(delta.files.first?.name, "c.json")
    }

    func testTwoDeviceSyncThroughFolder() async throws {
        let store = try FolderRemoteStore(root: tempDir())
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        let dbA = try AppDatabase.inMemoryMigrated()
        let repoA = CardRepository(dbA, deviceID: "A", now: { t0 })
        let engineA = SyncEngine(repository: repoA, remote: store, now: { t0 })

        let dbB = try AppDatabase.inMemoryMigrated()
        let repoB = CardRepository(dbB, deviceID: "B", now: { t0 })
        let engineB = SyncEngine(repository: repoB, remote: store, now: { t0 })

        let card = try repoA.create(Card(familyName: "山田", company: "ABC"))
        _ = try await engineA.sync()
        _ = try await engineB.sync()

        let onB = try XCTUnwrap(try repoB.fetchOne(id: card.id))
        XCTAssertEqual(onB.company, "ABC")
        XCTAssertFalse(onB.dirty)
    }
}
