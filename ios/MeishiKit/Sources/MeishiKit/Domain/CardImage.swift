import Foundation

/// 名刺画像。1カードに複数枚(表/裏)を紐づけられる。
///
/// 確定#4: 初版UIは「表1枚」に絞るが、DBは最初から表裏対応にしておき、
/// 裏面UIは Phase 1.5 で解放する(手戻りゼロ)。
public struct CardImage: Codable, Identifiable, Equatable, Sendable {

    public var id: String
    /// 紐づく Card.id。
    public var cardId: String
    /// 表/裏。
    public var side: Side
    /// アプリ領域からの相対パス(絶対パスは端末間で変わるため保持しない)。
    public var relativePath: String
    /// 画像の SHA-256(重複画像検出・同期の同一性判定に使用)。
    public var sha256: String
    public var width: Int?
    public var height: Int?
    public var createdAt: Date

    public enum Side: String, Codable, Sendable, CaseIterable {
        case front
        case back
    }

    public init(
        id: String = UUID().uuidString,
        cardId: String,
        side: Side = .front,
        relativePath: String,
        sha256: String,
        width: Int? = nil,
        height: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.cardId = cardId
        self.side = side
        self.relativePath = relativePath
        self.sha256 = sha256
        self.width = width
        self.height = height
        self.createdAt = createdAt
    }
}
