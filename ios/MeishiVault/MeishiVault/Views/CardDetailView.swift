import SwiftUI
import MeishiKit

/// 名刺の詳細。電話/メール/URL/住所はタップでアクション。編集・お気に入り・削除。
struct CardDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let cardId: String
    @State private var showEdit = false
    @State private var showAddToContacts = false
    @State private var showTagEditor = false
    @State private var vcardURL: URL?
    @State private var conflicts: [FieldConflictRecord] = []

    private var card: Card? { model.card(id: cardId) }

    var body: some View {
        if let card {
            List {
                if let image = model.frontImage(for: card) {
                    Section {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                if !conflicts.isEmpty {
                    conflictSection(for: card)
                }

                Section("氏名") {
                    labeledRow("氏名", card.displayName)
                    if let kana = kanaText(card) { labeledRow("かな", kana) }
                }

                Section("所属") {
                    optionalRow("会社", card.company)
                    optionalRow("部署", card.department)
                    optionalRow("役職", card.title)
                }

                Section("連絡先") {
                    actionRow("メール", card.email, scheme: "mailto:")
                    actionRow("電話", card.phone, scheme: "tel:")
                    actionRow("携帯", card.mobile, scheme: "tel:")
                    optionalRow("FAX", card.fax)
                    optionalRow("郵便番号", card.postalCode)
                    addressRow(card.address)
                    linkRow(card.url)
                }

                Section("タグ") {
                    let tags = model.tags(for: card)
                    if tags.isEmpty {
                        Button {
                            showTagEditor = true
                        } label: {
                            Label("タグを追加", systemImage: "tag")
                        }
                    } else {
                        Button {
                            showTagEditor = true
                        } label: {
                            HStack {
                                TagChips(tags: tags)
                                Spacer()
                                Image(systemName: "pencil").foregroundStyle(.secondary)
                            }
                        }
                        .tint(.primary)
                    }
                }

                if let memo = card.memo, !memo.isEmpty {
                    Section("メモ") { Text(memo) }
                }

                Section {
                    Button {
                        showAddToContacts = true
                    } label: {
                        Label("連絡先に追加", systemImage: "person.crop.circle.badge.plus")
                    }
                }
            }
            .navigationTitle(card.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.toggleFavorite(card)
                    } label: {
                        Image(systemName: card.isFavorite ? "star.fill" : "star")
                    }
                    .tint(.yellow)
                    .accessibilityLabel(card.isFavorite ? "お気に入りを解除" : "お気に入りに追加")
                }
                if let vcardURL {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: vcardURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("vCardで共有")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("編集") { showEdit = true }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("削除", role: .destructive) {
                        model.delete(card)
                        dismiss()
                    }
                }
            }
            .task(id: card) {
                // 共有用の .vcf を用意(画像があれば埋め込む)。
                let photo = model.frontImage(for: card)?.jpegData(compressionQuality: 0.8)
                vcardURL = VCardExporter.temporaryFile(for: card, photoJPEG: photo)
                conflicts = model.conflicts(for: card)
            }
            .sheet(isPresented: $showEdit) {
                CardEditView(card: card)
            }
            .sheet(isPresented: $showAddToContacts) {
                AddToContactsView(
                    card: card,
                    imageData: model.frontImage(for: card)?.jpegData(compressionQuality: 0.8),
                    onFinish: { showAddToContacts = false }
                )
                }
            .sheet(isPresented: $showTagEditor) {
                TagEditorView(card: card)
            }
        } else {
            // 削除直後などで見つからない場合。
            ContentUnavailableView("名刺が見つかりません", systemImage: "questionmark.folder")
        }
    }

    // MARK: - 競合履歴(自動解決で負けた値)

    @ViewBuilder
    private func conflictSection(for card: Card) -> some View {
        Section {
            ForEach(conflicts) { conflict in
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.fieldLabel(conflict.field))
                        .font(.subheadline).bold()
                    Text("採用: \(conflict.winningValue ?? "(なし)")")
                        .font(.footnote)
                    Text("別端末の値: \(conflict.losingValue ?? "(なし)")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button("破棄", role: .destructive) {
                        model.dismissConflict(conflict)
                        conflicts = model.conflicts(for: card)
                    }
                }
            }
        } header: {
            Label("編集履歴(自動解決)", systemImage: "arrow.triangle.branch")
        } footer: {
            Text("別の端末と同時に編集され、新しい方を自動採用しました。古い値も残しています(スワイプで破棄)。")
        }
    }

    /// card.json のフィールド名 → 日本語ラベル。
    private static func fieldLabel(_ field: String) -> String {
        switch field {
        case CardFieldName.familyName, CardFieldName.givenName: return "氏名"
        case CardFieldName.familyNameKana, CardFieldName.givenNameKana: return "かな"
        case CardFieldName.company: return "会社"
        case CardFieldName.department: return "部署"
        case CardFieldName.title: return "役職"
        case CardFieldName.phone: return "電話"
        case CardFieldName.mobile: return "携帯"
        case CardFieldName.fax: return "FAX"
        case CardFieldName.email: return "メール"
        case CardFieldName.postalCode: return "郵便番号"
        case CardFieldName.address: return "住所"
        case CardFieldName.website: return "URL"
        case CardFieldName.memo: return "メモ"
        case CardFieldName.isFavorite: return "お気に入り"
        case CardFieldName.exchangedAt: return "交換日"
        default: return field
        }
    }

    // MARK: - 行

    private func labeledRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }

    @ViewBuilder
    private func optionalRow(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            labeledRow(label, value)
        }
    }

    @ViewBuilder
    private func actionRow(_ label: String, _ value: String?, scheme: String) -> some View {
        if let value, !value.isEmpty {
            Button {
                if let url = URL(string: scheme + value.replacingOccurrences(of: " ", with: "")) {
                    openURL(url)
                }
            } label: {
                labeledRow(label, value)
            }
            .tint(.primary)
        }
    }

    @ViewBuilder
    private func addressRow(_ address: String?) -> some View {
        if let address, !address.isEmpty {
            Button {
                let query = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let url = URL(string: "https://maps.apple.com/?q=\(query)") {
                    openURL(url)
                }
            } label: {
                labeledRow("住所", address)
            }
            .tint(.primary)
        }
    }

    @ViewBuilder
    private func linkRow(_ urlString: String?) -> some View {
        if let urlString, !urlString.isEmpty {
            Button {
                let normalized = urlString.hasPrefix("http") ? urlString : "https://\(urlString)"
                if let url = URL(string: normalized) { openURL(url) }
            } label: {
                labeledRow("URL", urlString)
            }
            .tint(.primary)
        }
    }

    private func kanaText(_ card: Card) -> String? {
        let kana = [card.familyNameKana, card.givenNameKana].compactMap { $0 }.joined(separator: " ")
        return kana.isEmpty ? nil : kana
    }
}
