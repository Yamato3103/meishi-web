import SwiftUI
import MeishiKit

/// 登録時に重複候補が見つかったときの解決画面。
/// 候補ごとに「マージ」、あるいは「別人として登録」/「キャンセル」を選ぶ。
struct DuplicateResolutionView: View {
    @Environment(AppModel.self) private var model

    let matches: [DuplicateMatch]
    /// 選んだ候補にマージする。
    let onMerge: (DuplicateMatch) -> Void
    /// 別人として新規登録する。
    let onRegisterAsNew: () -> Void
    /// 取り込みを中止する。
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("同じ人の名刺がすでにあるかもしれません。統合するか、別人として登録できます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("重複の候補") {
                    ForEach(matches, id: \.card.id) { match in
                        Button {
                            onMerge(match)
                        } label: {
                            candidateRow(match)
                        }
                        .tint(.primary)
                    }
                }
                Section {
                    Button("別人として登録") { onRegisterAsNew() }
                }
            }
            .navigationTitle("重複の確認")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onCancel() }
                }
            }
        }
    }

    private func candidateRow(_ match: DuplicateMatch) -> some View {
        HStack(spacing: 12) {
            thumbnail(match.card)
            VStack(alignment: .leading, spacing: 2) {
                Text(match.card.displayName).font(.headline)
                if let company = match.card.company, !company.isEmpty {
                    Text(company).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(match.isStrong ? "一致度: 高" : "一致度: 中")
                    .font(.caption2)
                    .foregroundStyle(match.isStrong ? .green : .orange)
            }
            Spacer()
            Label("マージ", systemImage: "arrow.triangle.merge")
                .labelStyle(.iconOnly)
                .foregroundStyle(.tint)
        }
        .padding(.vertical, 2)
    }

    private func thumbnail(_ card: Card) -> some View {
        Group {
            if let image = model.frontImage(for: card) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.rectangle").foregroundStyle(.secondary)
            }
        }
        .frame(width: 56, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
    }
}
