import SwiftUI
import MeishiKit

/// 名刺の編集フォーム。保存で revision++・FTS・正規化が更新される(Repository 経由)。
struct CardEditView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Card

    init(card: Card) {
        _draft = State(initialValue: card)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("氏名") {
                    field("姓", text: $draft.familyName)
                    field("名", text: $draft.givenName)
                    field("姓(かな)", text: $draft.familyNameKana)
                    field("名(かな)", text: $draft.givenNameKana)
                }
                Section("所属") {
                    field("会社名", text: $draft.company)
                    field("部署", text: $draft.department)
                    field("役職", text: $draft.title)
                }
                Section("連絡先") {
                    field("メール", text: $draft.email, keyboard: .emailAddress)
                    field("電話", text: $draft.phone, keyboard: .phonePad)
                    field("携帯", text: $draft.mobile, keyboard: .phonePad)
                    field("FAX", text: $draft.fax, keyboard: .phonePad)
                    field("郵便番号", text: $draft.postalCode, keyboard: .numbersAndPunctuation)
                    field("住所", text: $draft.address)
                    field("URL", text: $draft.url, keyboard: .URL)
                }
                Section("メモ") {
                    field("メモ", text: $draft.memo)
                }
                Section("お気に入り") {
                    Toggle("お気に入り", isOn: $draft.isFavorite)
                }
            }
            .navigationTitle("編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        model.update(draft)
                        dismiss()
                    }
                }
            }
        }
    }

    private func field(_ title: String, text: Binding<String?>, keyboard: UIKeyboardType = .default) -> some View {
        TextField(title, text: Binding(
            get: { text.wrappedValue ?? "" },
            set: { text.wrappedValue = $0.isEmpty ? nil : $0 }
        ))
        .keyboardType(keyboard)
    }
}
