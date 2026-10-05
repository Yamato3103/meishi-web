import SwiftUI

@main
struct MeishiVaultApp: App {
    @State private var model = AppModel()
    @State private var lock = AppLockController()
    @State private var tips = TipJarController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                if lock.isLocked {
                    LockScreen()
                }
            }
            .environment(model)
            .environment(model.sync)
            .environment(lock)
            .environment(tips)
            .task {
                if lock.isLocked { lock.authenticate() } else { syncIfPossible() }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background, .inactive:
                    // .inactive は .background 直前にも一瞬入る状態で、タスクスイッチャーの
                    // スナップショットはこのタイミングで撮られる。ここでロックしないと
                    // App Lock 有効時でも名刺一覧がスイッチャーに写り込む。
                    lock.lockIfNeeded()
                case .active:
                    if lock.isLocked { lock.authenticate() } else { syncIfPossible() }
                default:
                    break
                }
            }
            .onChange(of: lock.isLocked) { _, isLocked in
                // ロック解除直後にも同期する(起動時ロック→解除の経路)。
                if !isLocked { syncIfPossible() }
            }
        }
    }

    /// 同期が有効なら、起動/復帰時にバックグラウンドで同期する(実行は syncNow 内でガード)。
    private func syncIfPossible() {
        Task {
            await model.sync.syncNow()
            model.reload()
        }
    }
}
