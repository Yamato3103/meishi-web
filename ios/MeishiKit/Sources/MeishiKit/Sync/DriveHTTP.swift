import Foundation

/// アクセストークンの供給元。OAuth の実装(トークン取得・更新)を同期ロジックから分離する。
///
/// アプリ側が ASWebAuthenticationSession + PKCE で実装し、`GoogleDriveRemoteStore` は
/// 「有効なトークンをくれる何か」としてのみ依存する。これにより Drive ストアは UI/認可の
/// 実装に縛られず、テストでは固定トークンを返すだけの偽実装を差し込める。
public protocol DriveTokenProvider: Sendable {
    /// 有効なアクセストークンを返す(必要なら内部で更新する)。
    func accessToken() async throws -> String
}

/// 固定トークンを返す `DriveTokenProvider`(テスト・簡易利用向け)。
public struct StaticTokenProvider: DriveTokenProvider {
    private let token: String
    public init(_ token: String) { self.token = token }
    public func accessToken() async throws -> String { token }
}

/// HTTP レスポンス(継ぎ目用の最小表現)。
public struct HTTPResponse: Sendable {
    public let status: Int
    public let data: Data
    public let headers: [String: String]
    public init(status: Int, data: Data, headers: [String: String] = [:]) {
        self.status = status
        self.data = data
        self.headers = headers
    }
}

/// HTTP 送信の抽象(URLSession を直接使わないことで、Drive ロジックをモックで検証可能にする)。
public protocol DriveHTTP: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

/// URLSession 実装(本番)。
public struct URLSessionDriveHTTP: DriveHTTP {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DriveError.invalidResponse
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let k = key as? String, let v = value as? String { headers[k] = v }
        }
        return HTTPResponse(status: http.statusCode, data: data, headers: headers)
    }
}

/// Drive 連携のエラー。
public enum DriveError: Error, Equatable, Sendable {
    case invalidResponse
    case http(status: Int, body: String)
    case decoding(String)
    case notFound(String)
}
