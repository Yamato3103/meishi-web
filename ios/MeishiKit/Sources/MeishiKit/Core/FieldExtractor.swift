import Foundation

/// 決定論的フィールド抽出エンジン。
///
/// クラウドAI不使用。正規表現 + ラベル + 辞書 + レイアウト(座標)で
/// OcrDocument から各フィールドを推定する。振る舞いは spec/ の
/// extraction-rules.json と test-vectors/ で固定する(回帰テストで担保)。
///
/// 注: spec の単一文字ラベル("T"/"F"/"M" 等)は誤検出が大きいため実装では採用せず、
/// 多文字ラベルのみを使う(意図的な逸脱)。
public enum FieldExtractor {

    public static func extract(from document: OcrDocument) -> ExtractionResult {
        var result = ExtractionResult()

        // 各行を NFKC 正規化して扱う。
        let lines = document.lines.map { Normalizer.nfkc($0.text) }
        let bboxes = document.lines.map(\.bbox)

        // 氏名候補から除外する行(会社/部署/役職/連絡先など)を記録する。
        var claimed = Set<Int>()

        // MARK: メール
        for (i, line) in lines.enumerated() {
            for m in regexMatches(Patterns.email, in: line) {
                let value = m.lowercased()
                result.email.append(Candidate(value: value, confidence: 0.96,
                                               sourceLineIndices: [i], normalizedKey: Normalizer.email(value)))
                claimed.insert(i)
            }
        }

        // MARK: URL / SNS(メールにマッチした部分は除外)
        for (i, line) in lines.enumerated() {
            for m in regexMatches(Patterns.sns, in: line) {
                result.sns.append(Candidate(value: m, confidence: 0.8, sourceLineIndices: [i]))
                claimed.insert(i)
            }
            for m in regexMatches(Patterns.urlHttp, in: line) {
                result.url.append(Candidate(value: m, confidence: 0.95, sourceLineIndices: [i]))
                claimed.insert(i)
            }
            for m in regexMatches(Patterns.urlWww, in: line) where !isPartOfEmail(m, in: line) {
                result.url.append(Candidate(value: m, confidence: 0.8, sourceLineIndices: [i]))
                claimed.insert(i)
            }
        }

        // MARK: 郵便番号(〒を含む行を優先)
        if let postal = firstMatch(Patterns.postal, inLines: lines, preferContaining: "〒") {
            result.postalCode = Candidate(value: postal.value, confidence: 0.9, sourceLineIndices: [postal.index])
        }

        // MARK: 電話 / FAX / 携帯(ラベルで種別を確定 → 未ラベルは番号形状で補完)
        var claimedNumbers = Set<String>()

        // 携帯(ラベル or 携帯番号形状)
        for (i, line) in lines.enumerated() {
            let hasLabel = containsAny(line, Dictionaries.mobileLabels)
            let numbers = regexMatches(Patterns.mobileNumber, in: line)
            for n in numbers {
                let conf = hasLabel ? 0.9 : 0.75
                result.mobile.append(Candidate(value: n, confidence: conf,
                                               sourceLineIndices: [i], normalizedKey: digitsOnly(n)))
                claimedNumbers.insert(digitsOnly(n))
                claimed.insert(i)
            }
        }
        // FAX(ラベル必須。1行に TEL と FAX が並ぶ名刺があるので、番号ごとにラベルで判定する)
        for (i, line) in lines.enumerated() {
            for (n, isFax) in classifyNumbers(in: line) where isFax && !claimedNumbers.contains(digitsOnly(n)) {
                result.fax.append(Candidate(value: n, confidence: 0.9,
                                            sourceLineIndices: [i], normalizedKey: digitsOnly(n)))
                claimedNumbers.insert(digitsOnly(n))
                claimed.insert(i)
            }
        }
        // 固定電話(ラベル → 0.9、未ラベルの番号 → 0.6)
        for (i, line) in lines.enumerated() {
            let hasLabel = containsAny(line, Dictionaries.phoneLabels)
            for n in regexMatches(Patterns.phoneNumber, in: line) where !claimedNumbers.contains(digitsOnly(n)) {
                let conf = hasLabel ? 0.9 : 0.6
                result.phone.append(Candidate(value: n, confidence: conf,
                                              sourceLineIndices: [i], normalizedKey: digitsOnly(n)))
                claimedNumbers.insert(digitsOnly(n))
                if hasLabel { claimed.insert(i) }
            }
        }

        // MARK: 会社(法人格を含む行 → 無ければ上部の大きい行)
        if let idx = lines.firstIndex(where: { containsAny($0, Dictionaries.corporateSuffixes) }) {
            result.company = Candidate(value: lines[idx], confidence: 0.9,
                                       sourceLineIndices: [idx], normalizedKey: Normalizer.companyKey(lines[idx]))
            claimed.insert(idx)
        }

        // MARK: 役職(「営業部 課長」のように部署と同じ行なら分け合う)
        let titleIdx = lines.firstIndex(where: { containsAny($0, Dictionaries.titles) })
        let titleSplit = titleIdx.flatMap { splitDepartmentAndTitle(lines[$0]) }
        if let idx = titleIdx {
            result.title = Candidate(value: titleSplit?.title ?? lines[idx], confidence: 0.8, sourceLineIndices: [idx])
            claimed.insert(idx)
        }

        // MARK: 部署(会社の行は除外。役職だけの行は部署にしない)
        for (i, line) in lines.enumerated() where i != claimedCompanyIndex(result, lines) {
            if i == titleIdx {
                guard let split = titleSplit else { continue }
                result.department = Candidate(value: split.department, confidence: 0.7, sourceLineIndices: [i])
                break
            }
            if containsAny(line, Dictionaries.departmentTokens) {
                result.department = Candidate(value: line, confidence: 0.7, sourceLineIndices: [i])
                claimed.insert(i)
                break
            }
        }

        // MARK: 住所(都道府県を含む行)
        if let idx = lines.firstIndex(where: { containsAny($0, Dictionaries.prefectures) }) {
            result.address = Candidate(value: lines[idx], confidence: 0.75, sourceLineIndices: [idx])
            claimed.insert(idx)
        }

        // MARK: 氏名(会社/部署/役職/連絡先でない行のうち、bbox.h が最大)
        let nameCandidates = lines.indices.filter { i in
            !claimed.contains(i)
            && !lines[i].contains("@")
            && !containsDigit(lines[i])
            && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty
        }
        if let nameIdx = nameCandidates.max(by: { bboxes[$0].h < bboxes[$1].h }) {
            result.personName = PersonName(
                full: Candidate(value: lines[nameIdx], confidence: 0.6, sourceLineIndices: [nameIdx])
            )
            // ふりがな: 氏名候補に隣接する、かなのみの小さい行。
            if let kanaIdx = furiganaIndex(near: nameIdx, lines: lines, bboxes: bboxes) {
                let parts = lines[kanaIdx].split(whereSeparator: { $0 == " " || $0 == "\u{3000}" }).map(String.init)
                if let family = parts.first {
                    result.personName?.familyKana = Candidate(value: family, confidence: 0.55, sourceLineIndices: [kanaIdx])
                }
                if parts.count > 1 {
                    result.personName?.givenKana = Candidate(value: parts[1], confidence: 0.55, sourceLineIndices: [kanaIdx])
                }
            }
        }

        return result
    }

    // MARK: - ヘルパー

    private static func claimedCompanyIndex(_ result: ExtractionResult, _ lines: [String]) -> Int? {
        guard let value = result.company?.value else { return nil }
        return lines.firstIndex(of: value)
    }

    /// 氏名行の直上/直下にある、かなのみ・より小さい行の index。
    private static func furiganaIndex(near nameIdx: Int, lines: [String], bboxes: [OcrDocument.BBox]) -> Int? {
        let nameY = bboxes[nameIdx].y
        let candidates = lines.indices.filter { i in
            i != nameIdx
            && isKanaOnly(lines[i])
            && bboxes[i].h <= bboxes[nameIdx].h
            && abs(bboxes[i].y - nameY) < 0.12
        }
        return candidates.min(by: { abs(bboxes[$0].y - nameY) < abs(bboxes[$1].y - nameY) })
    }

    private static func isKanaOnly(_ text: String) -> Bool {
        let trimmed = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{3000}", with: "")
        guard !trimmed.isEmpty else { return false }
        for scalar in trimmed.unicodeScalars {
            let v = scalar.value
            let isHiragana = (0x3041...0x309F).contains(v)
            let isKatakana = (0x30A0...0x30FF).contains(v)
            if !(isHiragana || isKatakana) { return false }
        }
        return true
    }

    /// 1行の電話番号を、直前のラベル(無ければ直後のラベル、それも無ければ行全体)で TEL / FAX に分ける。
    /// "TEL 03-1234-5678 / FAX 03-1234-5679" のような並びで、両方を FAX にしないため。
    private static func classifyNumbers(in line: String) -> [(value: String, isFax: Bool)] {
        guard let re = try? NSRegularExpression(pattern: Patterns.phoneNumber) else { return [] }
        let ns = line as NSString
        let found = re.matches(in: line, range: NSRange(location: 0, length: ns.length))
        let lineHasFax = containsAny(line, Dictionaries.faxLabels)
        let lineHasPhone = containsAny(line, Dictionaries.phoneLabels)
        var prevEnd = 0
        var out: [(value: String, isFax: Bool)] = []
        for (k, m) in found.enumerated() {
            let value = ns.substring(with: m.range)
            let end = m.range.location + m.range.length
            let before = ns.substring(with: NSRange(location: prevEnd, length: m.range.location - prevEnd))
            let nextStart = k + 1 < found.count ? found[k + 1].range.location : ns.length
            let after = ns.substring(with: NSRange(location: end, length: nextStart - end))
            prevEnd = end

            let beforeFax = lastLabelEnd(in: before, Dictionaries.faxLabels)
            let beforePhone = lastLabelEnd(in: before, Dictionaries.phoneLabels)
            if beforeFax != beforePhone { out.append((value, beforeFax > beforePhone)); continue }
            let afterFax = firstLabelStart(in: after, Dictionaries.faxLabels)
            let afterPhone = firstLabelStart(in: after, Dictionaries.phoneLabels)
            if afterFax != afterPhone { out.append((value, afterFax < afterPhone)); continue }
            out.append((value, lineHasFax && !lineHasPhone))
        }
        return out
    }

    /// text 内で最後に現れるラベルの終端位置(無ければ -1)。
    private static func lastLabelEnd(in text: String, _ labels: [String]) -> Int {
        let ns = text as NSString
        return labels.map { label -> Int in
            let r = ns.range(of: label, options: .backwards)
            return r.location == NSNotFound ? -1 : r.location + r.length
        }.max() ?? -1
    }

    /// text 内で最初に現れるラベルの開始位置(無ければ Int.max)。
    private static func firstLabelStart(in text: String, _ labels: [String]) -> Int {
        let ns = text as NSString
        return labels.map { label -> Int in
            let r = ns.range(of: label)
            return r.location == NSNotFound ? Int.max : r.location
        }.min() ?? Int.max
    }

    /// 「営業本部 第一営業部  課長」のように部署と役職が1行に並ぶとき、役職語の手前を部署、
    /// そこから後ろを役職に分ける。手前に部署語が無ければ(「営業部長」など)分けない。
    private static func splitDepartmentAndTitle(_ line: String) -> (department: String, title: String)? {
        let ns = line as NSString
        var start = -1
        for t in Dictionaries.titles {
            let r = ns.range(of: t)
            if r.location == NSNotFound { continue }
            if start < 0 || r.location < start { start = r.location }
        }
        guard start > 0 else { return nil }
        let department = ns.substring(to: start).trimmingCharacters(in: .whitespaces)
        let title = ns.substring(from: start).trimmingCharacters(in: .whitespaces)
        guard !department.isEmpty, containsAny(department, Dictionaries.departmentTokens) else { return nil }
        return (department, title)
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private static func containsDigit(_ text: String) -> Bool {
        text.unicodeScalars.contains { ("0"..."9").contains(Character($0)) }
    }

    private static func digitsOnly(_ text: String) -> String {
        String(text.unicodeScalars.filter { ("0"..."9").contains(Character($0)) })
    }

    private static func isPartOfEmail(_ substring: String, in line: String) -> Bool {
        !regexMatches(Patterns.email, in: line).filter { $0.contains(substring) }.isEmpty
    }

    private static func regexMatches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }
    }

    private static func firstMatch(_ pattern: String, inLines lines: [String], preferContaining marker: String) -> (index: Int, value: String)? {
        // marker を含む行を優先。
        let ordered = lines.indices.sorted { a, b in
            let aHas = lines[a].contains(marker), bHas = lines[b].contains(marker)
            return (aHas ? 0 : 1) < (bHas ? 0 : 1)
        }
        for i in ordered {
            if let m = regexMatches(pattern, in: lines[i]).first {
                return (i, m)
            }
        }
        return nil
    }

    // MARK: - パターン / 辞書

    private enum Patterns {
        static let email = "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        static let urlHttp = "https?://[A-Za-z0-9./?#@%&=_~+-]+"
        static let urlWww = "www\\.[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        static let sns = "(https?://)?(www\\.)?(twitter|facebook|instagram|linkedin)\\.com/[A-Za-z0-9._/-]+"
        static let postal = "[0-9]{3}-[0-9]{4}"
        static let mobileNumber = "0[789]0-?[0-9]{4}-?[0-9]{4}"
        static let phoneNumber = "0[0-9]{1,3}-[0-9]{1,4}-[0-9]{3,4}"
    }

    private enum Dictionaries {
        static let mobileLabels = ["携帯", "Mobile", "Cell", "モバイル"]
        static let faxLabels = ["FAX", "Fax", "fax", "ファックス", "ファクス"]
        static let phoneLabels = ["TEL", "Tel", "tel", "電話", "℡", "代表", "Phone"]
        static let corporateSuffixes = [
            "株式会社", "有限会社", "合同会社", "合資会社", "合名会社",
            "一般社団法人", "公益社団法人", "一般財団法人", "公益財団法人",
            "(株)", "(有)", "(株)", "(有)",
            "Co., Ltd.", "Co.,Ltd.", "Corporation", "Corp.", "Inc.", "Inc",
            "K.K.", "LLC", "Ltd.", "Ltd", "Company"
        ]
        static let titles = [
            "代表取締役社長", "代表取締役", "取締役会長", "取締役", "執行役員",
            "会長", "社長", "副社長", "専務", "常務", "監査役",
            "本部長", "部長", "次長", "課長", "係長", "主任", "主査",
            "マネージャー", "ディレクター", "プロデューサー", "エンジニア", "デザイナー",
            "代表", "CEO", "COO", "CTO", "CFO", "President", "Director", "Manager", "Engineer"
        ]
        static let departmentTokens = [
            "事業部", "本部", "統括部", "部", "課", "室", "グループ", "チーム",
            "支店", "営業所", "支社", "センター", "研究所", "Division", "Department", "Group", "Team"
        ]
        static let prefectures = [
            "北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県",
            "茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県",
            "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県", "岐阜県",
            "静岡県", "愛知県", "三重県", "滋賀県", "京都府", "大阪府", "兵庫県",
            "奈良県", "和歌山県", "鳥取県", "島根県", "岡山県", "広島県", "山口県",
            "徳島県", "香川県", "愛媛県", "高知県", "福岡県", "佐賀県", "長崎県",
            "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県"
        ]
    }
}
