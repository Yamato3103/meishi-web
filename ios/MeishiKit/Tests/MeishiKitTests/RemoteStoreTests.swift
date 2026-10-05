import XCTest
@testable import MeishiKit

final class RemoteStoreTests: XCTestCase {

    func testWriteReadListDelete() async throws {
        let store = InMemoryRemoteStore()
        let meta = try await store.write(name: "a.json", data: Data("hello".utf8), ifMatch: nil)

        let read = try await store.read(id: meta.id)
        XCTAssertEqual(String(decoding: read, as: UTF8.self), "hello")

        let listed = try await store.list()
        XCTAssertEqual(listed.map { $0.name }, ["a.json"])

        try await store.delete(id: meta.id)
        let afterDelete = try await store.list()
        XCTAssertTrue(afterDelete.isEmpty)
    }

    func testOptimisticLockRejectsStaleWrite() async throws {
        let store = InMemoryRemoteStore()
        let v1 = try await store.write(name: "c.json", data: Data("1".utf8), ifMatch: nil)
        // 正しい revision なら成功。
        let v2 = try await store.write(name: "c.json", data: Data("2".utf8), ifMatch: v1.revision)
        XCTAssertNotEqual(v1.revision, v2.revision)

        // 古い revision での上書きは衝突。
        do {
            _ = try await store.write(name: "c.json", data: Data("3".utf8), ifMatch: v1.revision)
            XCTFail("stale write should conflict")
        } catch let error as RemoteConflictError {
            XCTAssertEqual(error.expected, v1.revision)
            XCTAssertEqual(error.actual, v2.revision)
        }
    }

    func testChangesReturnsDeltaSinceToken() async throws {
        let store = InMemoryRemoteStore()
        // 初回はトークン確立のみ、差分は空。
        let bootstrap = try await store.changes(since: nil)
        XCTAssertTrue(bootstrap.files.isEmpty)

        await store.seed(name: "a.json", data: Data("a".utf8))
        await store.seed(name: "b.json", data: Data("b".utf8))

        let delta = try await store.changes(since: bootstrap.nextToken)
        XCTAssertEqual(Set(delta.files.map { $0.name }), ["a.json", "b.json"])

        // 消費後は差分なし。
        let empty = try await store.changes(since: delta.nextToken)
        XCTAssertTrue(empty.files.isEmpty)
    }

    func testDeleteShowsAsTombstoneInChanges() async throws {
        let store = InMemoryRemoteStore()
        let bootstrap = try await store.changes(since: nil)
        let meta = try await store.write(name: "d.json", data: Data("x".utf8), ifMatch: nil)
        _ = try await store.changes(since: bootstrap.nextToken) // 消費
        let tokenAfterWrite = try await store.changes(since: bootstrap.nextToken).nextToken

        try await store.delete(id: meta.id)
        let delta = try await store.changes(since: tokenAfterWrite)
        XCTAssertEqual(delta.files.first?.name, "d.json")
        XCTAssertTrue(delta.files.first?.deleted ?? false)
    }

    func testCardDocumentThroughRemoteStore() async throws {
        // card.json をリモット経由で往復できること(結合の最小確認)。
        let store = InMemoryRemoteStore()
        let card = Card(id: "card-9", familyName: "田中", company: "XYZ",
                        createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 1),
                        revision: 1, deviceId: "dev")
        let doc = CardDocument(card: card)
        let meta = try await store.write(name: "\(card.id).json", data: try doc.encoded(), ifMatch: nil)

        let fetched = try CardDocument.decoded(try await store.read(id: meta.id))
        XCTAssertEqual(fetched.toCard().familyName, "田中")
        XCTAssertEqual(fetched.toCard().company, "XYZ")
    }
}
