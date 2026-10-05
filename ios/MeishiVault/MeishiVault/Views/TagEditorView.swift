import SwiftUI
import MeishiKit

/// カードにタグを付け外しする。既存タグの選択と、新規タグの作成に対応。
struct TagEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let card: Card

    @State private var allTags: [Tag] = []
    @State private var assignedIds: Set<String> = []
    @State private var newTagName = ""
    @State private var tagPendingDeletion: Tag?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("新しいタグ", text: $newTagName)
                            .onSubmit(addNewTag)
                        Button("追加", action: addNewTag)
                            .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                if allTags.isEmpty {
                    Section {
                        Text("タグがありません。上で作成できます。")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                } else {
                    Section("タグ") {
                        ForEach(allTags) { tag in
                            Button {
                                toggle(tag)
                            } label: {
                                HStack {
                                    Image(systemName: assignedIds.contains(tag.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(assignedIds.contains(tag.id) ? Color.accentColor : Color.secondary)
                                    Text(tag.name)
                                    Spacer()
                                }
                            }
                            .tint(.primary)
                        }
                        .onDelete(perform: confirmDelete)
                    }
                }
            }
            .navigationTitle("タグ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
            .onAppear(perform: refresh)
            .alert(
                "「\(tagPendingDeletion?.name ?? "")」を削除しますか?",
                isPresented: Binding(get: { tagPendingDeletion != nil }, set: { if !$0 { tagPendingDeletion = nil } })
            ) {
                Button("削除", role: .destructive, action: performDelete)
                Button("キャンセル", role: .cancel) { tagPendingDeletion = nil }
            } message: {
                Text("このタグはすべてのカードから削除されます。元に戻せません。")
            }
        }
    }

    private func refresh() {
        allTags = model.allTags()
        assignedIds = Set(model.tags(for: card).map(\.id))
    }

    private func toggle(_ tag: Tag) {
        let isOn = !assignedIds.contains(tag.id)
        model.setTag(tag, on: card, isOn: isOn)
        if isOn { assignedIds.insert(tag.id) } else { assignedIds.remove(tag.id) }
    }

    private func addNewTag() {
        let name = newTagName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        model.addTag(named: name, to: card)
        newTagName = ""
        refresh()
    }

    /// スワイプ削除はタグそのもの(全カード共通)を消すため、誤操作防止に確認を挟む。
    private func confirmDelete(at offsets: IndexSet) {
        guard let index = offsets.first else { return }
        tagPendingDeletion = allTags[index]
    }

    private func performDelete() {
        guard let tag = tagPendingDeletion else { return }
        model.deleteTag(tag)
        tagPendingDeletion = nil
        refresh()
    }
}
