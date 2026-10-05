import Foundation

/// 重複候補の1件(既存カード + スコア)。
public struct DuplicateMatch: Equatable, Sendable {
    public let card: Card
    public let score: Int
    public init(card: Card, score: Int) {
        self.card = card
        self.score = score
    }
    /// 強い一致(自動マージを勧められる水準)。
    public var isStrong: Bool { score >= DuplicateDetector.strongThreshold }
}

/// 重複検知のスコアリングとマージ規則(設計書 §8)。
///
/// メール一致を最重視し、電話・氏名・会社+姓で加点する。
/// ブロッキング(候補の絞り込み)は Repository 側で email_normalized /
/// company_normalized / 電話文字列を使って行い、ここは純粋なスコア計算に徹する。
public enum DuplicateDetector {

    /// これ以上を「重複候補」として提示する。
    public static let candidateThreshold = 40
    /// これ以上を「強い一致」とみなす。
    public static let strongThreshold = 60

    public static func score(_ a: Card, _ b: Card) -> Int {
        var score = 0

        // メール(正規化一致): +60
        if let ea = Normalizer.email(a.email), let eb = Normalizer.email(b.email), ea == eb {
            score += 60
        }

        // 電話/携帯/FAX の数字が1つでも一致: +40
        if !phoneDigits(a).isDisjoint(with: phoneDigits(b)) {
            score += 40
        }

        // フルネーム(正規化)一致: +30
        if let na = fullNameKey(a), let nb = fullNameKey(b), na == nb {
            score += 30
        }

        // 会社(正規化)一致 かつ 姓一致: +20
        if let ca = Normalizer.companyKey(a.company), let cb = Normalizer.companyKey(b.company), ca == cb,
           let fa = nameKey(a.familyName), let fb = nameKey(b.familyName), fa == fb {
            score += 20
        }

        return score
    }

    /// マージ結果(primary を基準に、空欄を secondary で補完)。純粋関数。
    public static func merged(primary: Card, secondary: Card) -> Card {
        var m = primary

        func fill(_ keyPath: WritableKeyPath<Card, String?>) {
            let current = m[keyPath: keyPath]
            if current == nil || current?.isEmpty == true {
                m[keyPath: keyPath] = secondary[keyPath: keyPath]
            }
        }

        fill(\.familyName); fill(\.givenName); fill(\.familyNameKana); fill(\.givenNameKana)
        fill(\.company); fill(\.department); fill(\.title)
        fill(\.email); fill(\.phone); fill(\.mobile); fill(\.fax)
        fill(\.postalCode); fill(\.address); fill(\.url)

        // メモは両方あれば連結。
        if let sm = secondary.memo, !sm.isEmpty {
            if let pm = m.memo, !pm.isEmpty {
                m.memo = pm + "\n" + sm
            } else {
                m.memo = sm
            }
        }

        m.isFavorite = primary.isFavorite || secondary.isFavorite
        if m.exchangedAt == nil { m.exchangedAt = secondary.exchangedAt }

        return m
    }

    // MARK: - ヘルパー

    static func phoneDigits(_ card: Card) -> Set<String> {
        var set = Set<String>()
        for raw in [card.phone, card.mobile, card.fax].compactMap({ $0 }) {
            let digits = raw.unicodeScalars.filter { ("0"..."9").contains(Character($0)) }.map(String.init).joined()
            if digits.count >= 7 { set.insert(digits) }
        }
        return set
    }

    static func fullNameKey(_ card: Card) -> String? {
        let joined = [card.familyName, card.givenName].compactMap { $0 }.joined()
        return nameKey(joined)
    }

    static func nameKey(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = Normalizer.nfkc(value)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{3000}", with: "")
        return normalized.isEmpty ? nil : normalized
    }
}
