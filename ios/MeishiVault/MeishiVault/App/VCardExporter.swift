import Foundation
import MeishiKit

/// vCard をファイルに書き出し、共有(ShareLink / 共有シート)に渡せる URL を返す。
enum VCardExporter {

    /// 複数カードを1つの .vcf に書き出す。失敗時は nil。
    static func temporaryFile(for cards: [Card], filename: String? = nil) -> URL? {
        guard !cards.isEmpty else { return nil }
        let text = VCardBuilder.build(cards: cards)
        let name = filename ?? defaultFilename(for: cards)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try text.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// 1枚を、画像付き(PHOTO 埋め込み)で書き出す。
    static func temporaryFile(for card: Card, photoJPEG: Data?) -> URL? {
        let text = VCardBuilder.build(card, photoJPEG: photoJPEG)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(defaultFilename(for: [card]))
        do {
            try text.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func defaultFilename(for cards: [Card]) -> String {
        if cards.count == 1, let card = cards.first {
            let base = VCardBuilder.fullName(card)
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: " ", with: "")
            return "\(base).vcf"
        }
        return "MeishiVault-\(cards.count)件.vcf"
    }
}
