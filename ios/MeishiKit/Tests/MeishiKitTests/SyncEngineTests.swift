import XCTest
@testable import MeishiKit

/// 2端末 + 共有インメモリストアで、フィールド単位LWW同期の収束を検証する。
final class SyncEngineTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ offset: TimeInterval) -> Date { t0.addingTimeInterval(offset) }

    /// 可変クロック(編集時刻を精密に制御し、フィールド別更新時刻を決める)。
    private final class Clock: @unchecked Sendable {
        var t: Date
        init(_ t: Date) { self.t = t }
    }

    private struct Node {
        let repo: CardRepository
        let engine: SyncEngine
        let clock: Clock
    }

    private func makeNode(_ device: String, store: InMemoryRemoteStore, at start: Date,
                          imageStore: ImageStore? = nil) throws -> Node {
        let db = try AppDatabase.inMemoryMigrated()
        let clock = Clock(start)
        let repo = CardRepository(db, deviceID: device, now: { clock.t })
        let engine = SyncEngine(repository: repo, remote: store, imageStore: imageStore, now: { clock.t })
        return Node(repo: repo, engine: engine, clock: clock)
    }

    private func tempImageStore() throws -> ImageStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeishiSyncTest-\(UUID().uuidString)", isDirectory: true)
        return try ImageStore(rootDirectory: dir)
    }

    func testBootstrapPropagatesNewCard() async throws {
        let store = InMemoryRemoteStore()
        let a = try makeNode("A", store: store, at: t0)
        let b = try makeNode("B", store: store, at: t0)

        let card = try a.repo.create(Card(familyName: "山田", company: "ABC"))
        _ = try await a.engine.sync()
        _ = try await b.engine.sync()

        let onB = try XCTUnwrap(try b.repo.fetchOne(id: card.id))
        XCTAssertEqual(onB.company, "ABC")
        XCTAssertEqual(onB.familyName, "山田")
        XCTAssertFalse(onB.dirty, "リモート由来は未同期ではない")
    }

    func testFieldLevelMergeConverges() async throws {
        let store = InMemoryRemoteStore()
        let a = try makeNode("A", store: store, at: t0)
        let b = try makeNode("B", store: store, at: t0)

        let card = try a.repo.create(Card(familyName: "山田", company: "orig", title: "orig"))
        _ = try await a.engine.sync()
        _ = try await b.engine.sync()

        // A は company を、B は title を別時刻で編集(異なるフィールド)。
        a.clock.t = at(100)
        var ca = try XCTUnwrap(try a.repo.fetchOne(id: card.id)); ca.company = "A社"
        _ = try a.repo.update(ca)
        b.clock.t = at(90)
        var cb = try XCTUnwrap(try b.repo.fetchOne(id: card.id)); cb.title = "B役職"
        _ = try b.repo.update(cb)

        _ = try await a.engine.sync()   // A push 成功
        _ = try await b.engine.sync()   // B push は衝突 → 取得してマージ → 再 push
        _ = try await a.engine.sync()   // A pull で B の title を取り込む

        let onA = try XCTUnwrap(try a.repo.fetchOne(id: card.id))
        let onB = try XCTUnwrap(try b.repo.fetchOne(id: card.id))
        XCTAssertEqual(onA.company, "A社"); XCTAssertEqual(onA.title, "B役職")
        XCTAssertEqual(onB.company, "A社"); XCTAssertEqual(onB.title, "B役職")
        XCTAssertFalse(onA.dirty); XCTAssertFalse(onB.dirty)
    }

    func testSameFieldConflictKeepsNewerAndRecordsLoser() async throws {
        let store = InMemoryRemoteStore()
        let a = try makeNode("A", store: store, at: t0)
        let b = try makeNode("B", store: store, at: t0)

        let card = try a.repo.create(Card(familyName: "山田", company: "orig"))
        _ = try await a.engine.sync()
        _ = try await b.engine.sync()

        // 同じ company を両方が編集。A の方が新しい。
        b.clock.t = at(50)
        var cb = try XCTUnwrap(try b.repo.fetchOne(id: card.id)); cb.company = "B社"
        _ = try b.repo.update(cb)
        a.clock.t = at(100)
        var ca = try XCTUnwrap(try a.repo.fetchOne(id: card.id)); ca.company = "A社"
        _ = try a.repo.update(ca)

        _ = try await a.engine.sync()            // A push (company=A社 @100)
        let bSum = try await b.engine.sync()     // B push 衝突 → マージ: A社 勝ち、B社 負け

        XCTAssertTrue(
            bSum.conflicts.contains { $0.field == CardFieldName.company && $0.losingValue == .string("B社") },
            "負けた B社 が編集履歴として残る(サイレントロス防止)"
        )
        // DB にも永続化され、名刺詳細から参照できる。
        let history = try b.repo.conflicts(forCardId: card.id)
        XCTAssertTrue(history.contains { $0.field == CardFieldName.company && $0.losingValue == "B社" && $0.winningValue == "A社" })

        _ = try await a.engine.sync()            // A pull で収束
        let onA = try XCTUnwrap(try a.repo.fetchOne(id: card.id))
        let onB = try XCTUnwrap(try b.repo.fetchOne(id: card.id))
        XCTAssertEqual(onA.company, "A社")
        XCTAssertEqual(onB.company, "A社")
    }

    func testDeletePropagatesAsTombstone() async throws {
        let store = InMemoryRemoteStore()
        let a = try makeNode("A", store: store, at: t0)
        let b = try makeNode("B", store: store, at: t0)

        let card = try a.repo.create(Card(familyName: "山田"))
        _ = try await a.engine.sync()
        _ = try await b.engine.sync()

        a.clock.t = at(200)
        try a.repo.softDelete(id: card.id)
        _ = try await a.engine.sync()
        let sum = try await b.engine.sync()

        XCTAssertEqual(sum.deletionsPulled, 1)
        let onB = try XCTUnwrap(try b.repo.fetchOne(id: card.id))
        XCTAssertTrue(onB.isDeleted, "削除は tombstone として伝播")
    }

    func testTagsPropagate() async throws {
        let store = InMemoryRemoteStore()
        let a = try makeNode("A", store: store, at: t0)
        let b = try makeNode("B", store: store, at: t0)

        let card = try a.repo.create(Card(familyName: "山田"))
        let tag = try a.repo.createOrGetTag(name: "取引先")
        try a.repo.addTag(tag.id, toCardId: card.id)

        _ = try await a.engine.sync()
        _ = try await b.engine.sync()

        XCTAssertEqual(try b.repo.tags(forCardId: card.id).map(\.name), ["取引先"])
    }

    func testImageBinaryTransfers() async throws {
        let store = InMemoryRemoteStore()
        let imgA = try tempImageStore()
        let imgB = try tempImageStore()
        let a = try makeNode("A", store: store, at: t0, imageStore: imgA)
        let b = try makeNode("B", store: store, at: t0, imageStore: imgB)

        let card = try a.repo.create(Card(familyName: "山田"))
        let bytes = Data("JPEG-BYTES-山田".utf8)
        let saved = try imgA.save(bytes, cardId: card.id, side: .front)
        _ = try a.repo.addImage(CardImage(cardId: card.id, side: .front,
                                          relativePath: saved.relativePath, sha256: saved.sha256))

        _ = try await a.engine.sync()
        _ = try await b.engine.sync()

        // B 側に画像バイナリが届き、DB 行も紐づく。
        XCTAssertTrue(imgB.exists(relativePath: saved.relativePath))
        XCTAssertEqual(try imgB.data(forRelativePath: saved.relativePath), bytes)
        XCTAssertEqual(try b.repo.fetchImages(cardID: card.id).map(\.sha256), [saved.sha256])
    }

    func testFieldTimestampsStampOnlyChangedFields() throws {
        let db = try AppDatabase.inMemoryMigrated()
        let clock = Clock(t0)
        let repo = CardRepository(db, deviceID: "X", now: { clock.t })

        let card = try repo.create(Card(familyName: "山田", company: "ABC"))
        let ts0 = try repo.fieldTimestamps(forCardId: card.id)
        XCTAssertEqual(ts0[CardFieldName.company], t0)
        XCTAssertEqual(ts0[CardFieldName.familyName], t0)

        clock.t = at(500)
        var c = try XCTUnwrap(try repo.fetchOne(id: card.id)); c.company = "XYZ"
        _ = try repo.update(c)

        let ts1 = try repo.fieldTimestamps(forCardId: card.id)
        XCTAssertEqual(ts1[CardFieldName.company], at(500), "変更フィールドは新時刻")
        XCTAssertEqual(ts1[CardFieldName.familyName], t0, "未変更フィールドは据え置き")
    }
}
