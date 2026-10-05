import Foundation

/// Google Drive を裏側にする `RemoteStore` 実装(Drive REST API v3、`drive.file` スコープ)。
///
/// - アプリがマイドライブ直下に作業フォルダ(既定 "MeishiVault")を作り、その中に
///   card.json と画像を置く(§6.2)。`drive.file` は「自アプリ作成ファイルのみ」可視のため、
///   フォルダ選択 UI は提供せず自動作成する。
/// - 楽観ロックはファイルの `version`(単調増加)を使った check-then-act で表現する
///   (厳密な If-Match(ETag)は将来の改良)。
///
/// ネットワーク送信は `DriveHTTP`、認可は `DriveTokenProvider` に委譲するため、
/// Google に接続せずとも REST ロジック(要求組み立て・応答解釈・競合判定)をモックで検証できる。
/// 実サインインの疎通は各自の Google Cloud OAuth クライアント設定が必要(docs/google-drive-setup.md)。
public actor GoogleDriveRemoteStore: RemoteStore {

    public nonisolated let displayName: String

    private let http: DriveHTTP
    private let tokens: DriveTokenProvider
    private let folderName: String
    private var cachedFolderId: String?

    private let apiBase = "https://www.googleapis.com/drive/v3"
    private let uploadBase = "https://www.googleapis.com/upload/drive/v3"
    private let folderMime = "application/vnd.google-apps.folder"

    public init(tokens: DriveTokenProvider, http: DriveHTTP = URLSessionDriveHTTP(),
                folderName: String = "MeishiVault", displayName: String = "Google Drive") {
        self.tokens = tokens
        self.http = http
        self.folderName = folderName
        self.displayName = displayName
    }

    // MARK: - RemoteStore

    public func list() async throws -> [RemoteFileMeta] {
        let folderId = try await ensureFolder()
        var metas: [RemoteFileMeta] = []
        var pageToken: String?
        repeat {
            var query = [
                "q": "'\(folderId)' in parents and trashed=false",
                "spaces": "drive",
                "fields": "nextPageToken,files(id,name,version,modifiedTime)",
                "pageSize": "1000"
            ]
            if let pageToken { query["pageToken"] = pageToken }
            let json = try await getJSON("\(apiBase)/files", query: query)
            for file in (json["files"] as? [[String: Any]]) ?? [] {
                if let meta = Self.meta(from: file, deleted: false) { metas.append(meta) }
            }
            pageToken = json["nextPageToken"] as? String
        } while pageToken != nil
        return metas.sorted { $0.name < $1.name }
    }

    public func read(id: String) async throws -> Data {
        try await requestData(makeRequest("\(apiBase)/files/\(id)", query: ["alt": "media"], method: "GET",
                                          token: try await tokens.accessToken()))
    }

    @discardableResult
    public func write(name: String, data: Data, ifMatch: String?) async throws -> RemoteFileMeta {
        let folderId = try await ensureFolder()
        if let existing = try await findFile(named: name, in: folderId) {
            if let ifMatch, ifMatch != existing.revision {
                throw RemoteConflictError(name: name, expected: ifMatch, actual: existing.revision)
            }
            return try await updateMedia(fileId: existing.id, name: name, data: data)
        } else {
            if let ifMatch {
                throw RemoteConflictError(name: name, expected: ifMatch, actual: "<absent>")
            }
            return try await createMultipart(name: name, data: data, parent: folderId)
        }
    }

    public func delete(id: String) async throws {
        let token = try await tokens.accessToken()
        let response = try await http.send(makeRequest("\(apiBase)/files/\(id)", method: "DELETE", token: token))
        try Self.ensureOK(response)
    }

    public func changes(since token: String?) async throws -> RemoteChanges {
        _ = try await ensureFolder()
        guard let token else {
            let json = try await getJSON("\(apiBase)/changes/startPageToken", query: ["fields": "startPageToken"])
            let start = json["startPageToken"] as? String ?? "1"
            return RemoteChanges(files: [], nextToken: start)
        }

        var files: [RemoteFileMeta] = []
        var pageToken: String? = token
        var newStartToken = token
        repeat {
            let query = [
                "pageToken": pageToken ?? token,
                "spaces": "drive",
                "fields": "newStartPageToken,nextPageToken,changes(fileId,removed,file(id,name,version,modifiedTime,trashed))"
            ]
            let json = try await getJSON("\(apiBase)/changes", query: query)
            for change in (json["changes"] as? [[String: Any]]) ?? [] {
                let removed = (change["removed"] as? Bool) ?? false
                if removed {
                    if let id = change["fileId"] as? String {
                        files.append(RemoteFileMeta(id: id, name: "", revision: "", deleted: true))
                    }
                } else if let file = change["file"] as? [String: Any] {
                    let trashed = (file["trashed"] as? Bool) ?? false
                    if let meta = Self.meta(from: file, deleted: trashed) { files.append(meta) }
                }
            }
            if let next = json["nextPageToken"] as? String {
                pageToken = next
            } else {
                newStartToken = (json["newStartPageToken"] as? String) ?? token
                pageToken = nil
            }
        } while pageToken != nil

        return RemoteChanges(files: files, nextToken: newStartToken)
    }

    // MARK: - フォルダ

    private func ensureFolder() async throws -> String {
        if let cachedFolderId { return cachedFolderId }
        // 既存の作業フォルダを探す(drive.file では自アプリ作成分のみ見える)。
        let query = [
            "q": "name='\(folderName)' and mimeType='\(folderMime)' and trashed=false",
            "spaces": "drive",
            "fields": "files(id,name)"
        ]
        let json = try await getJSON("\(apiBase)/files", query: query)
        if let first = (json["files"] as? [[String: Any]])?.first, let id = first["id"] as? String {
            cachedFolderId = id
            return id
        }
        // 無ければ作成する。
        let body = try JSONSerialization.data(withJSONObject: [
            "name": folderName, "mimeType": folderMime
        ])
        var request = makeRequest("\(apiBase)/files", query: ["fields": "id"], method: "POST",
                                  token: try await tokens.accessToken())
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let created = try await sendJSON(request)
        guard let id = created["id"] as? String else { throw DriveError.decoding("folder id") }
        cachedFolderId = id
        return id
    }

    private func findFile(named name: String, in folderId: String) async throws -> RemoteFileMeta? {
        let escaped = name.replacingOccurrences(of: "'", with: "\\'")
        let query = [
            "q": "name='\(escaped)' and '\(folderId)' in parents and trashed=false",
            "spaces": "drive",
            "fields": "files(id,name,version,modifiedTime)"
        ]
        let json = try await getJSON("\(apiBase)/files", query: query)
        guard let first = (json["files"] as? [[String: Any]])?.first else { return nil }
        return Self.meta(from: first, deleted: false)
    }

    // MARK: - アップロード

    private func updateMedia(fileId: String, name: String, data: Data) async throws -> RemoteFileMeta {
        var request = makeRequest("\(uploadBase)/files/\(fileId)",
                                  query: ["uploadType": "media", "fields": "id,name,version,modifiedTime"],
                                  method: "PATCH", token: try await tokens.accessToken())
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let json = try await sendJSON(request)
        guard let meta = Self.meta(from: json, deleted: false, fallbackName: name) else {
            throw DriveError.decoding("update media response")
        }
        return meta
    }

    private func createMultipart(name: String, data: Data, parent: String) async throws -> RemoteFileMeta {
        let boundary = "meishi-\(UUID().uuidString)"
        let metadata = try JSONSerialization.data(withJSONObject: [
            "name": name, "parents": [parent]
        ])

        var body = Data()
        func append(_ string: String) { body.append(string.data(using: .utf8)!) }
        append("--\(boundary)\r\n")
        append("Content-Type: application/json; charset=UTF-8\r\n\r\n")
        body.append(metadata)
        append("\r\n--\(boundary)\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")

        var request = makeRequest("\(uploadBase)/files",
                                  query: ["uploadType": "multipart", "fields": "id,name,version,modifiedTime"],
                                  method: "POST", token: try await tokens.accessToken())
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let json = try await sendJSON(request)
        guard let meta = Self.meta(from: json, deleted: false, fallbackName: name) else {
            throw DriveError.decoding("create response")
        }
        return meta
    }

    // MARK: - 低レベル HTTP

    private func makeRequest(_ base: String, query: [String: String] = [:], method: String, token: String) -> URLRequest {
        var components = URLComponents(string: base)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func getJSON(_ base: String, query: [String: String]) async throws -> [String: Any] {
        let request = makeRequest(base, query: query, method: "GET", token: try await tokens.accessToken())
        return try await sendJSON(request)
    }

    private func sendJSON(_ request: URLRequest) async throws -> [String: Any] {
        let response = try await http.send(request)
        try Self.ensureOK(response)
        guard let object = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
            throw DriveError.decoding("expected JSON object")
        }
        return object
    }

    private func requestData(_ request: URLRequest) async throws -> Data {
        let response = try await http.send(request)
        try Self.ensureOK(response)
        return response.data
    }

    private static func ensureOK(_ response: HTTPResponse) throws {
        guard (200..<300).contains(response.status) else {
            throw DriveError.http(status: response.status, body: String(decoding: response.data, as: UTF8.self))
        }
    }

    private static func meta(from file: [String: Any], deleted: Bool, fallbackName: String = "") -> RemoteFileMeta? {
        guard let id = file["id"] as? String else { return nil }
        let name = (file["name"] as? String) ?? fallbackName
        // version は int64 が数値または文字列で来る。どちらも文字列化する。
        let version: String
        if let s = file["version"] as? String { version = s }
        else if let n = file["version"] as? NSNumber { version = n.stringValue }
        else { version = "" }
        let updatedAt = (file["modifiedTime"] as? String).flatMap(ISO8601.date(from:))
        return RemoteFileMeta(id: id, name: name, revision: version, updatedAt: updatedAt, deleted: deleted)
    }
}
