import Foundation
import LocalAuthentication

/// アプリロック(Face ID / パスコード)の状態管理。
///
/// 有効時は起動・復帰でロックし、`LocalAuthentication` で解除する。
/// 生体もパスコードも無い端末では解除不能を避けるため開錠扱いにする。
@MainActor
@Observable
final class AppLockController {

    private let enabledKey = "meishivault.app_lock_enabled"

    private(set) var isEnabled: Bool
    private(set) var isLocked: Bool

    init() {
        let enabled = UserDefaults.standard.bool(forKey: enabledKey)
        self.isEnabled = enabled
        // 有効なら最初はロック状態から始める。
        var locked = enabled
        #if DEBUG
        // 検証用: ロック画面のスクショ用に強制ロックを受け付ける。
        if ProcessInfo.processInfo.arguments.contains("--demo-locked") { locked = true }
        #endif
        self.isLocked = locked
    }

    /// 設定のオン/オフ。
    func setEnabled(_ newValue: Bool) {
        isEnabled = newValue
        UserDefaults.standard.set(newValue, forKey: enabledKey)
        isLocked = newValue ? isLocked : false
    }

    /// バックグラウンド遷移時などにロックする。
    func lockIfNeeded() {
        if isEnabled { isLocked = true }
    }

    /// 生体/パスコードで解除を試みる。
    func authenticate() {
        guard isLocked else { return }
        #if DEBUG
        // 検証用: 強制ロック中は自動解除しない(ロック画面のスクショ用)。
        if ProcessInfo.processInfo.arguments.contains("--demo-locked") { return }
        #endif

        let context = LAContext()
        var error: NSError?
        let policy: LAPolicy = .deviceOwnerAuthentication
        guard context.canEvaluatePolicy(policy, error: &error) else {
            // 認証手段が無い端末は解除できないため開ける。
            isLocked = false
            return
        }
        context.evaluatePolicy(policy, localizedReason: "名刺データのロックを解除します") { success, _ in
            Task { @MainActor in
                if success { self.isLocked = false }
            }
        }
    }
}
