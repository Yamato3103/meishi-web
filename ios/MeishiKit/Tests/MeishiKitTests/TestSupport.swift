import Foundation

/// 参照型の可変クロック。`@Sendable` な now クロージャから可変時刻を差し込むためのテスト補助。
final class MutableClock: @unchecked Sendable {
    var date: Date
    init(_ date: Date) { self.date = date }
}
