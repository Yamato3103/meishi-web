import SwiftUI
import StoreKit

/// 開発を応援する画面(Tip Jar)。額を複数表示し、購入後にお礼を出す。
///
/// 消費型 IAP で機能は解放しない。文言は「寄付」ではなく「応援 / チップ」。
struct TipJarView: View {
    @Environment(TipJarController.self) private var tips

    var body: some View {
        Form {
            Section {
                Text("MeishiVault はデータをサーバに預けず、端末内だけで完結する名刺管理です。無料でお使いいただけます。もし気に入っていただけたら、開発の応援(チップ)をいただけると励みになります。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                switch tips.loadState {
                case .idle, .loading:
                    HStack {
                        ProgressView()
                        Text("読み込み中…").foregroundStyle(.secondary)
                    }
                case .failed(let message):
                    Text(message).font(.footnote).foregroundStyle(.red)
                    Button("再読み込み") { Task { await tips.load() } }
                case .loaded:
                    if tips.products.isEmpty {
                        Text("応援メニューを取得できませんでした。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(tips.products, id: \.id) { product in
                            tipRow(product)
                        }
                    }
                }
            } header: {
                Text("開発を応援")
            } footer: {
                Text("チップをいただいても機能が増えることはありません。純粋な応援です。ありがとうございます。")
            }
        }
        .navigationTitle("開発を応援")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if case .loaded = tips.loadState {} else { await tips.load() }
        }
        .overlay {
            if tips.didThank { thanksOverlay }
        }
    }

    @ViewBuilder
    private func tipRow(_ product: Product) -> some View {
        Button {
            Task { await tips.tip(product) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName)
                    if !product.description.isEmpty {
                        Text(product.description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if tips.purchasingID == product.id {
                    ProgressView()
                } else {
                    Text(product.displayPrice)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
        }
        .disabled(tips.purchasingID != nil)
    }

    private var thanksOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.pink)
                Text("ありがとうございます!")
                    .font(.headline)
                Text("応援は開発の大きな励みになります。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("閉じる") { tips.dismissThanks() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(40)
        }
    }
}
