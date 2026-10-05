import Foundation
import CryptoKit
import AuthenticationServices
import UIKit
import MeishiKit

/// Google Drive の OAuth(Authorization Code + PKCE)を担う。
///
/// `drive.file` スコープのみ要求する(§6.1)。アクセストークンはメモリ、リフレッシュ
/// トークンは Keychain に保存し、`accessToken()` で必要に応じてサイレント更新する。
/// `MeishiKit.GoogleDriveRemoteStore` は本型を `DriveTokenProvider` として使う。
///
/// 実サインインの疎通には各自の Google Cloud OAuth クライアント ID が必要
/// (Info.plist の `GoogleDriveOAuth`。手順は docs/google-drive-setup.md)。未設定なら
/// `isConfigured == false` となり、UI 側で接続導線を隠す。
actor GoogleDriveAuth: DriveTokenProvider {

    struct Config: Sendable {
        let clientID: String
        let redirectScheme: String
        var redirectURI: String { "\(redirectScheme):/oauth2redirect" }
    }

    enum AuthError: Error, Equatable {
        case notConfigured, notConnected, noCode, tokenExchangeFailed(String)
    }

    private let config: Config?
    private var accessTokenValue: String?
    private var expiry: Date = .distantPast

    private let refreshKey = "meishivault.drive.refreshToken"
    private let scope = "https://www.googleapis.com/auth/drive.file"
    private let authEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenEndpoint = "https://oauth2.googleapis.com/token"

    init() { self.config = GoogleDriveAuth.loadConfig() }

    nonisolated var isConfigured: Bool { config != nil }

    var isConnected: Bool { Keychain.get(refreshKey) != nil }

    // MARK: - DriveTokenProvider

    func accessToken() async throws -> String {
        if let token = accessTokenValue, expiry > Date().addingTimeInterval(60) {
            return token
        }
        guard let refresh = Keychain.get(refreshKey) else { throw AuthError.notConnected }
        return try await refreshAccessToken(refresh)
    }

    // MARK: - 接続

    /// 対話サインインを行い、トークンを取得・保存する。
    func connect() async throws {
        guard let config else { throw AuthError.notConfigured }
        let verifier = Self.randomURLSafe(byteCount: 32)
        let challenge = Self.codeChallenge(for: verifier)

        var components = URLComponents(string: authEndpoint)!
        components.queryItems = [
            .init(name: "client_id", value: config.clientID),
            .init(name: "redirect_uri", value: config.redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent")
        ]

        let callback = try await WebAuthPresenter.shared.start(
            url: components.url!, scheme: config.redirectScheme)
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.noCode
        }
        try await exchange(code: code, verifier: verifier, config: config)
    }

    func disconnect() {
        Keychain.delete(refreshKey)
        accessTokenValue = nil
        expiry = .distantPast
    }

    // MARK: - トークン交換 / 更新

    private func exchange(code: String, verifier: String, config: Config) async throws {
        let params = [
            "client_id": config.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": config.redirectURI
        ]
        let json = try await postForm(tokenEndpoint, params: params)
        applyTokens(json)
        if let refresh = json["refresh_token"] as? String {
            Keychain.set(refresh, for: refreshKey)
        }
    }

    private func refreshAccessToken(_ refreshToken: String) async throws -> String {
        guard let config else { throw AuthError.notConfigured }
        let params = [
            "client_id": config.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        let json = try await postForm(tokenEndpoint, params: params)
        applyTokens(json)
        guard let token = accessTokenValue else { throw AuthError.tokenExchangeFailed("no access_token") }
        return token
    }

    private func applyTokens(_ json: [String: Any]) {
        if let access = json["access_token"] as? String {
            accessTokenValue = access
            let ttl = (json["expires_in"] as? NSNumber)?.doubleValue ?? 3300
            expiry = Date().addingTimeInterval(ttl)
        }
    }

    private func postForm(_ endpoint: String, params: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = params
            .map { "\($0.key)=\(Self.formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.tokenExchangeFailed(String(decoding: data, as: UTF8.self))
        }
        return json
    }

    // MARK: - PKCE ヘルパ

    private static func randomURLSafe(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return base64URL(Data(bytes))
    }

    private static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func loadConfig() -> Config? {
        guard let dict = Bundle.main.object(forInfoDictionaryKey: "GoogleDriveOAuth") as? [String: Any],
              let clientID = dict["ClientID"] as? String, !clientID.isEmpty,
              let scheme = dict["RedirectScheme"] as? String, !scheme.isEmpty else {
            return nil
        }
        return Config(clientID: clientID, redirectScheme: scheme)
    }
}

/// ASWebAuthenticationSession を提示し、コールバック URL を返す(要 MainActor)。
@MainActor
final class WebAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthPresenter()
    private var session: ASWebAuthenticationSession?

    func start(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: error ?? GoogleDriveAuth.AuthError.noCode)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: GoogleDriveAuth.AuthError.tokenExchangeFailed("cannot start session"))
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        return windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

/// 最小の Keychain ラッパ(リフレッシュトークン保管用)。
enum Keychain {
    static func set(_ value: String, for key: String) {
        delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
