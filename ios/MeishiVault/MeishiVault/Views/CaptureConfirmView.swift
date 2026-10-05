import SwiftUI
import MeishiKit

/// 取り込み確認画面。補正後画像のプレビューと、OCR 抽出結果で初期化された編集フォーム。
/// ユーザーは各欄を確認・修正して保存する(OCR が空でも手入力で登録可能)。
struct CaptureConfirmView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let processed: ImagePipeline.Processed

    @State private var draft: Card
    @State private var saveError: String?
    @State private var duplicateMatches: [DuplicateMatch] = []
    @State private var showDuplicates = false

    init(processed: ImagePipeline.Processed, draft: Card) {
        self.processed = processed
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("プレビュー") {
                    Image(uiImage: processed.image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
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
                if let saveError {
                    Section { Text(saveError).foregroundStyle(.red) }
                }
            }
            .navigationTitle("取り込みの確認")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .sheet(isPresented: $showDuplicates) {
                DuplicateResolutionView(
                    matches: duplicateMatches,
                    onMerge: { match in mergeInto(match) },
                    onRegisterAsNew: { registerAsNew() },
                    onCancel: { showDuplicates = false }
                )
            }
        }
    }

    /// nil を許容する String? 用の TextField。
    private func field(_ title: String, text: Binding<String?>, keyboard: UIKeyboardType = .default) -> some View {
        TextField(title, text: Binding(
            get: { text.wrappedValue ?? "" },
            set: { text.wrappedValue = $0.isEmpty ? nil : $0 }
        ))
        .keyboardType(keyboard)
    }

    private func save() {
        // 登録前に重複候補をチェック。あれば解決画面へ、なければそのまま保存。
        let matches = model.findDuplicates(of: draft)
        if matches.isEmpty {
            performImport()
        } else {
            duplicateMatches = matches
            showDuplicates = true
        }
    }

    /// 重複なしの通常保存。
    private func performImport() {
        do {
            try model.importCard(processed: processed, draft: draft)
            dismiss()
        } catch {
            saveError = "保存に失敗しました: \(error.localizedDescription)"
        }
    }

    /// 選んだ候補にマージ: 新規カードを作ってから候補へ統合する。
    private func mergeInto(_ match: DuplicateMatch) {
        do {
            let created = try model.importCard(processed: processed, draft: draft)
            model.merge(keeping: match.card, removing: created)
            showDuplicates = false
            dismiss()
        } catch {
            showDuplicates = false
            saveError = "マージに失敗しました: \(error.localizedDescription)"
        }
    }

    /// 別人として登録し、候補との「別人」ペアを記録する。
    private func registerAsNew() {
        do {
            let created = try model.importCard(processed: processed, draft: draft)
            for match in duplicateMatches {
                model.markNotDuplicate(created, match.card)
            }
            showDuplicates = false
            dismiss()
        } catch {
            showDuplicates = false
            saveError = "保存に失敗しました: \(error.localizedDescription)"
        }
    }
}
