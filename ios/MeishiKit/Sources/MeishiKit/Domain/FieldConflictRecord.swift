import Foundation

/// 同期のフィールド単位LWWで「負けた」値の記録(§5.3 のサイレントデータロス防止)。
///
/// 自動解決したうえで、負けた値を名刺詳細の「編集履歴」として提示できるように保持する。
/// ユーザーが確認したら破棄できる(dismiss)。
public struct FieldConflictRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var cardId: String
    /// card.json のフィールド名(例: "company")。表示名は UI 側で対応付ける。
    public var field: String
    /// 採用されなかった値(表示用テキスト)。
    public var losingValue: String?
    /// 採用された値(表示用テキスト)。
    public var winningValue: String?
    public var losingAt: Date
    public var winningAt: Date
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        cardId: String,
        field: String,
        losingValue: String?,
        winningValue: String?,
        losingAt: Date,
        winningAt: Date,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.cardId = cardId
        self.field = field
        self.losingValue = losingValue
        self.winningValue = winningValue
        self.losingAt = losingAt
        self.winningAt = winningAt
        self.createdAt = createdAt
    }
}
