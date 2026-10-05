import SwiftUI

/// 初回起動時の説明。価値(端末内・預けない)と、これから求める権限を先に伝える。
struct OnboardingView: View {
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            Image(systemName: "person.crop.rectangle.stack.fill")
                .font(.system(size: 60))
                .foregroundStyle(.tint)
                .padding(.bottom, 12)
            Text("MeishiVault")
                .font(.largeTitle.bold())
            Text("データを預からない名刺管理")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 32)

            VStack(alignment: .leading, spacing: 24) {
                point(icon: "lock.shield", title: "データは端末の中だけ",
                      body: "名刺は運営者に渡りません。あなたの iPhone に保存されます。")
                point(icon: "wifi.slash", title: "オフラインでも動く",
                      body: "撮影も文字認識(OCR)も端末内で完結。ネット接続は不要です。")
                point(icon: "camera.viewfinder", title: "権限について",
                      body: "名刺の撮影にカメラ、既存写真の取り込みに写真ライブラリを使います。")
            }
            .padding(.horizontal, 8)

            Spacer()

            Button(action: onDone) {
                Text("はじめる")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
        .multilineTextAlignment(.center)
    }

    private func point(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(body).font(.subheadline).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
    }
}
