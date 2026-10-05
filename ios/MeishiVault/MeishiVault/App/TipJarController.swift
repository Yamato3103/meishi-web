import Foundation
import StoreKit

/// 開発を応援するチップ(Tip Jar)の状態管理。
///
/// StoreKit 2 の**消費型 IAP**。機能は一切解放しない ―
/// 額を選んで購入 → `Transaction.finish` するだけ。
/// 「寄付(donation)」は認定 NPO 等しか IAP で集められないため、
/// 個人開発では文言・実装ともに「応援 / チップ」に寄せる。
@MainActor
@Observable
final class TipJarController {

    /// 消費型 IAP の商品ID(App Store Connect と `.storekit` で一致させる)。
    static let productIDs = [
        "com.meishivault.app.tip.small",
        "com.meishivault.app.tip.medium",
        "com.meishivault.app.tip.large",
    ]

    enum LoadState {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var products: [Product] = []
    private(set) var loadState: LoadState = .idle
    /// 直近の購入が成立したら true。お礼表示に使う。
    private(set) var didThank = false
    /// 購入処理中の商品ID(ボタンのスピナー用)。
    private(set) var purchasingID: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        // アプリ外(App Store のプロモ等)からの取引も finish するため常時監視。
        // このコントローラはアプリ生存期間の @State なので明示 cancel は不要
        // (@MainActor の deinit からは main-actor 隔離の updatesTask に触れられない)。
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.finish(update)
            }
        }
    }

    /// 商品を読み込み、価格の安い順に並べる。
    func load() async {
        loadState = .loading
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = loaded.sorted { $0.price < $1.price }
            loadState = .loaded
        } catch {
            loadState = .failed("商品を読み込めませんでした。時間をおいて再度お試しください。")
        }
    }

    /// 応援(チップ)を購入する。機能解放はせず、取引を finish するだけ。
    func tip(_ product: Product) async {
        guard purchasingID == nil else { return }
        purchasingID = product.id
        defer { purchasingID = nil }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                didThank = await finish(verification)
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            // 購入エラーは黙って無視(ユーザー操作でリトライ可能)。
        }
    }

    /// お礼表示を閉じる。
    func dismissThanks() {
        didThank = false
    }

    /// 検証済みの取引だけを finish する(消費型なので状態は残さない)。verified なら true を返す。
    @discardableResult
    private func finish(_ verification: VerificationResult<Transaction>) async -> Bool {
        guard case .verified(let transaction) = verification else { return false }
        await transaction.finish()
        return true
    }
}
