import Foundation
import MeishiKit

/// 同期のアプリ側コントローラ。
///
/// Phase 2 の同期先は 2 系統:
/// - **フォルダ**(`FolderRemoteStore`)= ユーザー所有フォルダ(端末内 / 将来 iCloud Drive)。
///   サーバにデータを預けないゼロ設定の既定経路。
/// - **Google Drive**(`GoogleDriveRemoteStore` + OAuth `drive.file`)= 任意。要 OAuth 設定。
@MainActor
@Observable
final class SyncController {

    enum Backend: String, CaseIterable {
        case folder
        case googleDrive
        var label: String {
            switch self {
            case .folder: return "フォルダ"
            case .googleDrive: return "Google Drive"
            }
        }
    }

    private let repository: CardRepository
    private let imageStore: ImageStore
    private let folderURL: URL
    private let driveAuth = GoogleDriveAuth()

    private var folderStore: FolderRemoteStore?
    private var driveStore: GoogleDriveRemoteStore?

    private let enabledKey = "meishivault.sync.folderEnabled"
    private let lastSyncedKey = "meishivault.sync.lastSynced"
    private let backendKey = "meishivault.sync.backend"

    private(set) var isEnabled: Bool
    private(set) var backend: Backend
    private(set) var isSyncing = false
    private(set) var lastSyncedAt: Date?
    private(set) var lastSummary: SyncSummary?
    private(set) var errorMessage: String?

    /// OAuth クライアントが設定済みか(Info.plist の GoogleDriveOAuth)。
    let isDriveConfigured: Bool
    /// Drive にサインイン済みか(Keychain のリフレッシュトークン有無をキャッシュ)。
    private(set) var isDriveConnected = false

    init(repository: CardRepository, imageStore: ImageStore) {
        self.repository = repository
        self.imageStore = imageStore
        self.folderURL = URL.documentsDirectory.appending(path: "MeishiVaultSync")
        self.isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        self.lastSyncedAt = UserDefaults.standard.object(forKey: lastSyncedKey) as? Date
        self.backend = Backend(rawValue: UserDefaults.standard.string(forKey: backendKey) ?? "") ?? .folder
        self.isDriveConfigured = driveAuth.isConfigured
        Task { await refreshDriveConnection() }
    }

    var folderDisplayName: String { folderURL.lastPathComponent }

    func setEnabled(_ on: Bool) {
        isEnabled = on
        UserDefaults.standard.set(on, forKey: enabledKey)
    }

    func setBackend(_ backend: Backend) {
        self.backend = backend
        UserDefaults.standard.set(backend.rawValue, forKey: backendKey)
    }

    // MARK: - Google Drive 接続

    func connectDrive() async {
        errorMessage = nil
        do {
            try await driveAuth.connect()
            await refreshDriveConnection()
            setBackend(.googleDrive)
        } catch {
            errorMessage = "Google Drive の接続に失敗しました: \(error.localizedDescription)"
        }
    }

    func disconnectDrive() async {
        await driveAuth.disconnect()
        await refreshDriveConnection()
        if backend == .googleDrive { setBackend(.folder) }
    }

    private func refreshDriveConnection() async {
        isDriveConnected = await driveAuth.isConnected
    }

    // MARK: - 同期

    @discardableResult
    func syncNow() async -> SyncSummary? {
        guard isEnabled, !isSyncing else { return nil }
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }
        do {
            let remote = try remoteStore()
            let engine = SyncEngine(repository: repository, remote: remote, imageStore: imageStore)
            let summary = try await engine.sync()
            lastSummary = summary
            lastSyncedAt = Date()
            UserDefaults.standard.set(lastSyncedAt, forKey: lastSyncedKey)
            return summary
        } catch {
            errorMessage = "同期に失敗しました: \(error.localizedDescription)"
            return nil
        }
    }

    private func remoteStore() throws -> any RemoteStore {
        switch backend {
        case .folder:
            if let folderStore { return folderStore }
            let store = try FolderRemoteStore(root: folderURL, displayName: "ローカルフォルダ")
            folderStore = store
            return store
        case .googleDrive:
            if let driveStore { return driveStore }
            let store = GoogleDriveRemoteStore(tokens: driveAuth)
            driveStore = store
            return store
        }
    }
}
