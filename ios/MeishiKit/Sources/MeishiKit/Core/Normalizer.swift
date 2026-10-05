import Foundation

/// 突合キー生成のための正規化ユーティリティ。
///
/// 抽出結果の「表示値」は原文を維持し、ここで作る正規化値は
/// 検索・重複検知(E6)の突合キーとして別カラムに保持する。
/// M1-B では最小限(NFKC + メール小文字化 + 会社の法人格サフィックス除去)のみ。
/// かな抽出や会社名のさらなる正規化は E4/E6 で拡張する。
public enum Normalizer {

    /// NFKC 正規化(全角英数・記号を半角へ、互換文字を統一)。
    public static func nfkc(_ string: String) -> String {
        string.precomposedStringWithCompatibilityMapping
    }

    /// メールアドレスの突合キー。NFKC + 前後空白除去 + 小文字化。
    /// - Returns: 空文字は `nil` に畳む。
    public static func email(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let normalized = nfkc(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    /// 会社名の突合キー。NFKC + 法人格サフィックス/プレフィックス除去 + 空白畳み。
    /// 例: "株式会社サンプル商事" → "サンプル商事"、"Sample Co., Ltd." → "Sample"。
    public static func companyKey(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var value = nfkc(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        for affix in corporateAffixes {
            value = value.replacingOccurrences(of: affix, with: " ")
        }
        // 連続空白を1つに畳み、前後を除去。
        let collapsed = value
            .split(whereSeparator: { $0 == " " || $0 == "\u{3000}" })
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    /// 除去対象の法人格表記(前後どちらに付いても除去する）。
    /// spec/rules/extraction-rules.json の companyNormalizationForKey と整合させる。
    static let corporateAffixes: [String] = [
        "株式会社", "有限会社", "合同会社", "合資会社", "合名会社",
        "(株)", "(有)", "(株)", "(有)",
        "Co., Ltd.", "Co.,Ltd.", "Corporation", "Corp.",
        "Inc.", "K.K.", "LLC", "Ltd.", "Ltd"
    ]
}
