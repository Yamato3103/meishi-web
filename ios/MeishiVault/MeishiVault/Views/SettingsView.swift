import SwiftUI
import UniformTypeIdentifiers

/// 設定。App Lock・最近削除・バックアップ(書き出し/復元)・バージョン。
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(SyncController.self) private var sync
    @Environment(AppLockController.self) private var lock
    @Environment(\.dismiss) private var dismiss

    @State private var backupURL: URL?
    @State private var showImporter = false
    @State private var importMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("App Lock(Face ID)", isOn: Binding(
                        get: { lock.isEnabled },
                        set: { lock.setEnabled($0) }
                    ))
                } header: {
                    Text("セキュリティ")
                } footer: {
                    Text("オンにすると、起動・復帰時に Face ID かパスコードで解除します。")
                }

                Section("名刺") {
                    NavigationLink {
                        RecentlyDeletedView()
                    } label: {
                        Label("最近削除", systemImage: "trash")
                    }
                }

                syncSection

                Section {
                    if let backupURL {
                        ShareLink(item: backupURL) {
                            Label("バックアップを書き出す", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("バックアップから復元", systemImage: "square.and.arrow.down")
                    }
                    if let importMessage {
                        Text(importMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("バックアップ")
                } footer: {
                    Text("端末内の全名刺と画像を1つのファイルに書き出します。復元は新規のみ取り込みます。")
                }

                Section {
                    NavigationLink {
                        TipJarView()
                    } label: {
                        Label("開発を応援", systemImage: "heart")
                    }
                } footer: {
                    Text("チップで開発を応援できます(任意)。機能は無料のままで変わりません。")
                }

                Section {
                    LabeledContent("バージョン", value: appVersion)
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
            .onAppear {
                backupURL = model.exportBackupFile()
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    let count = model.importBackup(from: url)
                    importMessage = "\(count)件を復元しました。"
                    backupURL = model.exportBackupFile()
                case .failure:
                    importMessage = "復元に失敗しました。"
                }
            }
        }
    }

    @ViewBuilder
    private var syncSection: some View {
        Section {
            Toggle("同期を有効にする", isOn: Binding(
                get: { sync.isEnabled },
                set: { sync.setEnabled($0) }
            ))
            if sync.isEnabled {
                if sync.isDriveConfigured {
                    Picker("保存先", selection: Binding(
                        get: { sync.backend },
                        set: { sync.setBackend($0) }
                    )) {
                        ForEach(SyncController.Backend.allCases, id: \.self) { backend in
                            Text(backend.label).tag(backend)
                        }
                    }
                    if sync.backend == .googleDrive {
                        driveConnectRow
                    }
                }

                if sync.backend == .folder {
                    LabeledContent("フォルダ", value: sync.folderDisplayName)
                }

                Button {
                    Task {
                        await sync.syncNow()
                        model.reload()
                    }
                } label: {
                    HStack {
                        Label("今すぐ同期", systemImage: "arrow.triangle.2.circlepath")
                        if sync.isSyncing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(sync.isSyncing)

                if let last = sync.lastSyncedAt {
                    LabeledContent("最終同期", value: last.formatted(date: .abbreviated, time: .shortened))
                }
                if let summary = sync.lastSummary {
                    Text("送信 \(summary.pushed) ・ 受信 \(summary.pulled) ・ 競合 \(summary.conflicts.count)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error = sync.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
        } header: {
            Text("同期")
        } footer: {
            if sync.isDriveConfigured {
                Text("名刺と画像を card.json 形式で保存します。フォルダ(端末内 / iCloud Drive)か、あなたの Google Drive(drive.file スコープ)を選べます。いずれもサーバには預けません。")
            } else {
                Text("名刺と画像を、あなた自身のフォルダ(端末内 / 将来 iCloud Drive)に card.json 形式で保存します。サーバには預けません。Google Drive を使うには OAuth 設定が必要です(docs/google-drive-setup.md)。")
            }
        }
    }

    @ViewBuilder
    private var driveConnectRow: some View {
        if sync.isDriveConnected {
            HStack {
                Label("接続済み", systemImage: "checkmark.seal")
                    .foregroundStyle(.green)
                Spacer()
                Button("切断", role: .destructive) {
                    Task { await sync.disconnectDrive() }
                }
            }
        } else {
            Button {
                Task { await sync.connectDrive() }
            } label: {
                Label("Google Drive に接続", systemImage: "person.badge.key")
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
