import SwiftUI

/// アプリロック中に全面を覆う画面。中身は見せない。
struct LockScreen: View {
    @Environment(AppLockController.self) private var lock

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThickMaterial)
                .ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("ロックされています")
                    .font(.headline)
                Button {
                    lock.authenticate()
                } label: {
                    Label("Face ID で解除", systemImage: "faceid")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
