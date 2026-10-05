import Foundation

/// タグ。名前は正規化(NFKC + 小文字)して一意にする。
public struct Tag: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString, name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}
