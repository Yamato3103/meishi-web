import Foundation

/// 抽出された1フィールドの候補。信頼度降順で保持し、確認UIで採用/修正する。
public struct Candidate: Codable, Equatable, Sendable {
    public var value: String
    public var confidence: Double
    /// 由来した OcrDocument.lines の index(確認UIの原画像ハイライト用)。
    public var sourceLineIndices: [Int]?
    /// 突合キー(電話の数字のみ版、会社の法人格除去版など)。重複検知で使用。
    public var normalizedKey: String?

    public init(value: String, confidence: Double, sourceLineIndices: [Int]? = nil, normalizedKey: String? = nil) {
        self.value = value
        self.confidence = confidence
        self.sourceLineIndices = sourceLineIndices
        self.normalizedKey = normalizedKey
    }
}

/// 氏名(ふりがな含む)。
public struct PersonName: Codable, Equatable, Sendable {
    public var full: Candidate?
    public var familyKana: Candidate?
    public var givenKana: Candidate?

    public init(full: Candidate? = nil, familyKana: Candidate? = nil, givenKana: Candidate? = nil) {
        self.full = full
        self.familyKana = familyKana
        self.givenKana = givenKana
    }

    public var isEmpty: Bool { full == nil && familyKana == nil && givenKana == nil }
}

/// 抽出エンジンの出力。詳細は spec/schema/extraction-result.schema.json と整合。
public struct ExtractionResult: Codable, Equatable, Sendable {
    public var email: [Candidate] = []
    public var url: [Candidate] = []
    public var phone: [Candidate] = []
    public var fax: [Candidate] = []
    public var mobile: [Candidate] = []
    public var sns: [Candidate] = []
    public var postalCode: Candidate?
    public var company: Candidate?
    public var department: Candidate?
    public var title: Candidate?
    public var address: Candidate?
    public var personName: PersonName?

    public init() {}
}
