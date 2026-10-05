import SwiftUI
import MeishiKit

/// 保存済み名刺の一覧(検索対応)。行タップで詳細へ遷移する。
struct CardListView: View {
    @Environment(AppModel.self) private var model
    let query: String

    @State private var selectedTag: Tag?

    private var cards: [Card] {
        let base = model.search(query)
        guard let selectedTag else { return base }
        let ids = model.cardIds(withTag: selectedTag)
        return base.filter { ids.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            tagFilterBar
            Group {
                if cards.isEmpty {
                    emptyState
                } else {
                    List(cards) { card in
                        NavigationLink(value: card) {
                            CardRow(card: card)
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var tagFilterBar: some View {
        let tags = model.allTags()
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(title: "すべて", isSelected: selectedTag == nil) { selectedTag = nil }
                    ForEach(tags) { tag in
                        filterChip(title: tag.name, isSelected: selectedTag?.id == tag.id) {
                            selectedTag = (selectedTag?.id == tag.id) ? nil : tag
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            Divider()
        }
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if query.isEmpty {
            ContentUnavailableView(
                "名刺がありません",
                systemImage: "person.crop.rectangle.stack",
                description: Text("右上のボタンから名刺を取り込みます。")
            )
        } else {
            ContentUnavailableView.search(text: query)
        }
    }
}

/// 一覧の1行。サムネイル + 氏名 + 会社。
struct CardRow: View {
    @Environment(AppModel.self) private var model
    let card: Card

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if card.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    Text(card.displayName)
                        .font(.headline)
                }
                if let company = card.company, !company.isEmpty {
                    Text(company)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var thumbnail: some View {
        Group {
            if let image = model.frontImage(for: card) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.rectangle")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 64, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
    }
}

extension Card {
    /// 表示用の氏名(姓 名)。空なら代替表記。
    var displayName: String {
        let name = [familyName, givenName].compactMap { $0 }.joined(separator: " ")
        return name.isEmpty ? "(名前なし)" : name
    }
}
