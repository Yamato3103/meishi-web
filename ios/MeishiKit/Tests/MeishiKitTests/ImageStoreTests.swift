import XCTest
@testable import MeishiKit

final class ImageStoreTests: XCTestCase {

    private func makeStore() throws -> ImageStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("meishi-image-tests-\(UUID().uuidString)")
        return try ImageStore(rootDirectory: dir)
    }

    func testSaveWritesFileAndReturnsHash() throws {
        let store = try makeStore()
        let data = Data("hello".utf8)

        let saved = try store.save(data, cardId: "card1", side: .front)

        XCTAssertEqual(saved.byteCount, 5)
        // "hello" の SHA-256 は既知の固定値。
        XCTAssertEqual(
            saved.sha256,
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
        XCTAssertTrue(saved.relativePath.hasPrefix("card1-front-"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(forRelativePath: saved.relativePath).path))
    }

    func testRoundTripReadsBackSameData() throws {
        let store = try makeStore()
        let data = Data([0x00, 0x01, 0x02, 0xFF])

        let saved = try store.save(data, cardId: "c", side: .back, fileExtension: "png")
        let readBack = try store.data(forRelativePath: saved.relativePath)

        XCTAssertEqual(readBack, data)
        XCTAssertTrue(saved.relativePath.hasSuffix(".png"))
    }

    func testDeleteRemovesFileAndIsIdempotent() throws {
        let store = try makeStore()
        let saved = try store.save(Data("x".utf8), cardId: "c", side: .front)

        try store.delete(relativePath: saved.relativePath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(forRelativePath: saved.relativePath).path))
        // 2回目でもエラーにならない。
        XCTAssertNoThrow(try store.delete(relativePath: saved.relativePath))
    }

    func testSha256HexIsStable() {
        XCTAssertEqual(
            ImageStore.sha256Hex(Data("".utf8)),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }
}
