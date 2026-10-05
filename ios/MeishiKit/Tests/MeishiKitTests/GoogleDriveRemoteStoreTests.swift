import XCTest
@testable import MeishiKit

/// Google に接続せず、Drive REST の要求組み立て・応答解釈・競合判定を検証する。
/// `DriveHTTP` を差し替え、パス+クエリ(復号後)の部分一致で応答を返す偽サーバを使う。
final class GoogleDriveRemoteStoreTests: XCTestCase {

    private final class ScriptedDrive: DriveHTTP, @unchecked Sendable {
        struct Rule { let method: String; let contains: [String]; let response: HTTPResponse }
        private var rules: [Rule] = []
        private(set) var requests: [URLRequest] = []

        func on(_ method: String, contains: [String], json: [String: Any]) {
            let data = try! JSONSerialization.data(withJSONObject: json)
            rules.append(Rule(method: method, contains: contains, response: HTTPResponse(status: 200, data: data)))
        }
        func onData(_ method: String, contains: [String], data: Data) {
            rules.append(Rule(method: method, contains: contains, response: HTTPResponse(status: 200, data: data)))
        }

        func send(_ request: URLRequest) async throws -> HTTPResponse {
            requests.append(request)
            let comps = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            let query = (comps.queryItems ?? []).map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
            let hay = comps.path + "?" + query   // 復号済み
            for rule in rules where rule.method == (request.httpMethod ?? "GET") {
                if rule.contains.allSatisfy({ hay.contains($0) }) { return rule.response }
            }
            return HTTPResponse(status: 404, data: Data())
        }
    }

    private func makeStore(_ drive: ScriptedDrive) -> GoogleDriveRemoteStore {
        GoogleDriveRemoteStore(tokens: StaticTokenProvider("token-123"), http: drive)
    }

    private let folderRule = ["/drive/v3/files", "mimeType='application/vnd.google-apps.folder'"]

    func testListParsesFiles() async throws {
        let drive = ScriptedDrive()
        drive.on("GET", contains: folderRule, json: ["files": [["id": "folder1", "name": "MeishiVault"]]])
        drive.on("GET", contains: ["/drive/v3/files", "in parents and trashed=false"], json: ["files": [
            ["id": "f1", "name": "a.json", "version": "3", "modifiedTime": "2026-08-08T06:16:21.000Z"],
            ["id": "f2", "name": "b.json", "version": "7", "modifiedTime": "2026-08-08T06:16:22.000Z"]
        ]])

        let metas = try await makeStore(drive).list()
        XCTAssertEqual(metas.map(\.name), ["a.json", "b.json"])
        XCTAssertEqual(metas.first?.revision, "3")
        XCTAssertNotNil(metas.first?.updatedAt)
        // すべての要求に Bearer トークンが付く。
        XCTAssertTrue(drive.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer token-123" })
    }

    func testWriteCreatesWhenAbsent() async throws {
        let drive = ScriptedDrive()
        drive.on("GET", contains: folderRule, json: ["files": [["id": "folder1", "name": "MeishiVault"]]])
        drive.on("GET", contains: ["/drive/v3/files", "name='c.json'"], json: ["files": []])
        drive.on("POST", contains: ["/upload/drive/v3/files", "uploadType=multipart"],
                 json: ["id": "new1", "name": "c.json", "version": "1", "modifiedTime": "2026-08-08T06:16:21.000Z"])

        let meta = try await makeStore(drive).write(name: "c.json", data: Data("x".utf8), ifMatch: nil)
        XCTAssertEqual(meta.id, "new1")
        XCTAssertEqual(meta.revision, "1")
        XCTAssertTrue(drive.requests.contains {
            $0.httpMethod == "POST" && ($0.url?.absoluteString.contains("uploadType=multipart") ?? false)
        })
    }

    func testWriteUpdatesWhenPresentAndVersionMatches() async throws {
        let drive = ScriptedDrive()
        drive.on("GET", contains: folderRule, json: ["files": [["id": "folder1", "name": "MeishiVault"]]])
        drive.on("GET", contains: ["/drive/v3/files", "name='c.json'"],
                 json: ["files": [["id": "f9", "name": "c.json", "version": "5", "modifiedTime": "2026-08-08T06:16:21.000Z"]]])
        drive.on("PATCH", contains: ["/upload/drive/v3/files/f9", "uploadType=media"],
                 json: ["id": "f9", "name": "c.json", "version": "6", "modifiedTime": "2026-08-08T06:16:30.000Z"])

        let meta = try await makeStore(drive).write(name: "c.json", data: Data("y".utf8), ifMatch: "5")
        XCTAssertEqual(meta.revision, "6")
    }

    func testWriteConflictOnVersionMismatch() async throws {
        let drive = ScriptedDrive()
        drive.on("GET", contains: folderRule, json: ["files": [["id": "folder1", "name": "MeishiVault"]]])
        drive.on("GET", contains: ["/drive/v3/files", "name='c.json'"],
                 json: ["files": [["id": "f9", "name": "c.json", "version": "5", "modifiedTime": "2026-08-08T06:16:21.000Z"]]])

        do {
            _ = try await makeStore(drive).write(name: "c.json", data: Data("z".utf8), ifMatch: "3")
            XCTFail("stale version should conflict")
        } catch let error as RemoteConflictError {
            XCTAssertEqual(error.expected, "3")
            XCTAssertEqual(error.actual, "5")
        }
        // アップロードは一切行われない。
        XCTAssertFalse(drive.requests.contains { $0.url?.absoluteString.contains("/upload/") ?? false })
    }

    func testChangesStartTokenThenDelta() async throws {
        let drive = ScriptedDrive()
        drive.on("GET", contains: folderRule, json: ["files": [["id": "folder1", "name": "MeishiVault"]]])
        drive.on("GET", contains: ["/drive/v3/changes/startPageToken"], json: ["startPageToken": "100"])

        let boot = try await makeStore(drive).changes(since: nil)
        XCTAssertTrue(boot.files.isEmpty)
        XCTAssertEqual(boot.nextToken, "100")

        let drive2 = ScriptedDrive()
        drive2.on("GET", contains: folderRule, json: ["files": [["id": "folder1", "name": "MeishiVault"]]])
        drive2.on("GET", contains: ["/drive/v3/changes", "pageToken=100"], json: [
            "changes": [["file": ["id": "f1", "name": "a.json", "version": "4", "modifiedTime": "2026-08-08T06:16:21.000Z"]]],
            "newStartPageToken": "105"
        ])

        let delta = try await makeStore(drive2).changes(since: "100")
        XCTAssertEqual(delta.files.map(\.name), ["a.json"])
        XCTAssertEqual(delta.nextToken, "105")
    }

    func testReadFetchesMedia() async throws {
        let drive = ScriptedDrive()
        drive.onData("GET", contains: ["/drive/v3/files/f1", "alt=media"], data: Data("HELLO".utf8))
        let data = try await makeStore(drive).read(id: "f1")
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "HELLO")
    }

    func testHTTPErrorSurfaces() async throws {
        let drive = ScriptedDrive()
        // フォルダ探索で 403 → DriveError.http。
        let store = makeStore(drive)   // ルール無し → 404 を返す
        do {
            _ = try await store.list()
            XCTFail("should throw")
        } catch let error as DriveError {
            if case .http(let status, _) = error { XCTAssertEqual(status, 404) }
            else { XCTFail("unexpected: \(error)") }
        }
    }
}
