import SwiftUI
import MeishiKit

/// 最近削除。復元・完全削除ができる。保持期間(30日)経過分は起動時に自動パージ。
struct RecentlyDeletedView: View {
    @Environment(AppModel.self) private var model
    @State private var deleted: [Card] = []

    var body: some View {
        Group {
            if deleted.isEmpty {
                ContentUnavailableView("最近削除はありません", systemImage: "trash")
            } else {
                List(deleted) { card in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.displayName).font(.headline)
                            if let company = card.company, !company.isEmpty {
                                Text(company).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            model.permanentlyDelete(card)
                            refresh()
                        } label: {
                            Label("完全に削除", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            model.restore(card)
                            refresh()
                        } label: {
                            Label("復元", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.green)
                    }
                }
            }
        }
        .navigationTitle("最近削除")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        deleted = model.recentlyDeleted()
    }
}
