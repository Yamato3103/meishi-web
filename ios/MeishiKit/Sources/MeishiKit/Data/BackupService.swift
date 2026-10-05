import Foundation

/// ローカルバックアップの書き出し / 復元。
///
/// 全カード(削除除外)と画像を1つの自己完結 JSON(画像は base64 埋め込み)にまとめる。
/// 外部依存なしで生成・復元でき、ファイル1つで持ち運べる(zip 化は将来の最適化=確定#5)。
/// 復元は「新規のみ」(既存 id はスキップ)。
public enum BackupService {

    public static let currentVersion = 1

    public struct Archive: Codable, Sendable {
        public var version: Int
        public var exportedAt: Date
        public var cards: [Entry]

        public struct Entry: Codable, Sendable {
            public var card: Card
            public var images: [Image]
        }

        public struct Image: Codable, Sendable {
            public var meta: CardImage
            public var dataBase64: String
        }
    }

    /// 現在の全カード + 画像をアーカイブにして JSON バイト列を返す。
    public static func export(repository: CardRepository, imageStore: ImageStore) throws -> Data {
        let cards = try repository.fetchAll()
        var entries: [Archive.Entry] = []
        for card in cards {
            let images = try repository.fetchImages(cardID: card.id)
            let backupImages: [Archive.Image] = images.compactMap { image in
                guard let data = try? imageStore.data(forRelativePath: image.relativePath) else { return nil }
                return Archive.Image(meta: image, dataBase64: data.base64EncodedString())
            }
            entries.append(Archive.Entry(card: card, images: backupImages))
        }
        let archive = Archive(version: currentVersion, exportedAt: Date(), cards: entries)
        return try encoder().encode(archive)
    }

    public static func decode(_ data: Data) throws -> Archive {
        try decoder().decode(Archive.self, from: data)
    }

    /// アーカイブを復元する。既存 id はスキップ(新規のみ)。
    /// - Returns: 復元した件数。
    @discardableResult
    public static func restore(_ data: Data, into repository: CardRepository, imageStore: ImageStore) throws -> Int {
        let archive = try decode(data)
        var restored = 0
        for entry in archive.cards {
            if try repository.fetchOne(id: entry.card.id) != nil { continue }
            _ = try repository.create(entry.card)
            for image in entry.images {
                guard let imageData = Data(base64Encoded: image.dataBase64) else { continue }
                let ext = (image.meta.relativePath as NSString).pathExtension
                let saved = try imageStore.save(
                    imageData,
                    cardId: entry.card.id,
                    side: image.meta.side,
                    fileExtension: ext.isEmpty ? "jpg" : ext
                )
                try repository.addImage(CardImage(
                    cardId: entry.card.id,
                    side: image.meta.side,
                    relativePath: saved.relativePath,
                    sha256: saved.sha256,
                    width: image.meta.width,
                    height: image.meta.height
                ))
            }
            restored += 1
        }
        return restored
    }

    // MARK: - JSON

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
