import Foundation
import CryptoKit

/// 名刺画像ファイルの保存先を管理する。
///
/// 画像バイト列(JPEG/PNG)を受け取り、SHA-256 を算出して
/// アプリ領域に保存し、DB に記録する相対パスと sha256 を返す。
/// UIKit には依存しない(Data ベース)ので、画像の生成・補正・エンコードは
/// アプリ(Feature 層)側で行い、ここには確定したバイト列だけを渡す。
public struct ImageStore: Sendable {

    /// 画像を格納するルートディレクトリ(例: Application Support/CardImages)。
    public let rootDirectory: URL

    /// - Parameter rootDirectory: 保存先。存在しなければ作成する。
    public init(rootDirectory: URL) throws {
        self.rootDirectory = rootDirectory
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        applyDataProtection(to: rootDirectory)
    }

    /// 保存結果。DB(`CardImage`)へ記録するのに必要な値。
    public struct SavedImage: Equatable, Sendable {
        public let relativePath: String
        public let sha256: String
        public let byteCount: Int
    }

    /// 画像データを保存する。ファイル名は衝突しないよう sha256 の先頭を含める。
    @discardableResult
    public func save(
        _ data: Data,
        cardId: String,
        side: CardImage.Side,
        fileExtension: String = "jpg"
    ) throws -> SavedImage {
        let hash = Self.sha256Hex(data)
        let relativePath = "\(cardId)-\(side.rawValue)-\(hash.prefix(12)).\(fileExtension)"
        let fileURL = rootDirectory.appendingPathComponent(relativePath)
        try data.write(to: fileURL, options: .atomic)
        applyDataProtection(to: fileURL)
        return SavedImage(relativePath: relativePath, sha256: hash, byteCount: data.count)
    }

    /// 相対パスから絶対 URL を解決する(端末間で変わる絶対パスは DB に保存しない)。
    public func url(forRelativePath relativePath: String) -> URL {
        rootDirectory.appendingPathComponent(relativePath)
    }

    /// 保存済み画像を読み出す。
    public func data(forRelativePath relativePath: String) throws -> Data {
        try Data(contentsOf: url(forRelativePath: relativePath))
    }

    /// 指定の相対パスにファイルが存在するか。
    public func exists(relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: url(forRelativePath: relativePath).path)
    }

    /// リモートから取得したバイト列を、指定の相対パスへそのまま保存する(同期の取り込み用)。
    /// 画像は内容アドレス(sha256)で不変のため、ファイル名は送信側の relativePath をそのまま使う。
    public func saveRaw(_ data: Data, relativePath: String) throws {
        let fileURL = url(forRelativePath: relativePath)
        try data.write(to: fileURL, options: .atomic)
        applyDataProtection(to: fileURL)
    }

    /// 保存済み画像を削除する(存在しなくてもエラーにしない)。
    public func delete(relativePath: String) throws {
        let fileURL = url(forRelativePath: relativePath)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    /// バイト列の SHA-256 を 16 進小文字で返す。
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// iOS ではデバイスロック中の保護属性を付与する(T-901 の基礎)。
    private func applyDataProtection(to url: URL) {
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }
}
