import XCTest
@testable import MeishiKit

/// spec/test-vectors/*.json を読み込み、抽出エンジンの出力が期待値
/// (value 一致 + confidence >= minConfidence)を満たすか回帰検証する。
/// spec はパッケージ外(monorepo ルート)にあるため #filePath から相対解決する。
final class ExtractionTests: XCTestCase {

    /// ios/MeishiKit/Tests/MeishiKitTests/ から 5 階層上がると monorepo ルート(名刺管理/)。
    private var specDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // MeishiKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // MeishiKit
            .deletingLastPathComponent()   // ios
            .deletingLastPathComponent()   // 名刺管理
            .appendingPathComponent("spec")
    }

    func testStandardJapaneseVector() throws {
        try runVector(named: "001-standard-jp")
    }

    func testEnglishLabelsVector() throws {
        try runVector(named: "002-english-labels")
    }

    func testTelAndFaxOnSameLineVector() throws {
        try runVector(named: "003-tel-fax-same-line")
    }

    func testLabelVariantsVector() throws {
        try runVector(named: "004-label-variants")
    }

    // MARK: - ランナー

    private func runVector(named name: String) throws {
        let url = specDirectory.appendingPathComponent("test-vectors/\(name).json")
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let inputData = try JSONSerialization.data(withJSONObject: try XCTUnwrap(root["input"]))
        let document = try JSONDecoder().decode(OcrDocument.self, from: inputData)
        let result = FieldExtractor.extract(from: document)

        let expected = try XCTUnwrap(root["expected"] as? [String: Any])
        for (field, exp) in expected {
            try assertField(field, expected: exp, in: result, vector: name)
        }
    }

    private func assertField(_ field: String, expected: Any, in result: ExtractionResult, vector: String) throws {
        if field == "personName" {
            let obj = try XCTUnwrap(expected as? [String: Any])
            if let full = obj["full"] { assertCandidate(result.personName?.full, expected: full, label: "\(vector).personName.full") }
            if let fk = obj["familyKana"] { assertCandidate(result.personName?.familyKana, expected: fk, label: "\(vector).personName.familyKana") }
            if let gk = obj["givenKana"] { assertCandidate(result.personName?.givenKana, expected: gk, label: "\(vector).personName.givenKana") }
            return
        }

        if let list = expected as? [[String: Any]] {
            let candidates = listCandidates(field, in: result)
            for e in list {
                let value = e["value"] as! String
                let minConf = (e["minConfidence"] as? Double) ?? 0
                guard let match = candidates.first(where: { $0.value == value }) else {
                    XCTFail("[\(vector)] \(field): 期待値 '\(value)' が見つからない。実際: \(candidates.map(\.value))")
                    continue
                }
                XCTAssertGreaterThanOrEqual(match.confidence, minConf, "[\(vector)] \(field) '\(value)' の信頼度")
            }
            return
        }

        // 単一フィールド
        assertCandidate(singleCandidate(field, in: result), expected: expected, label: "\(vector).\(field)")
    }

    private func assertCandidate(_ candidate: Candidate?, expected: Any, label: String) {
        guard let obj = expected as? [String: Any], let value = obj["value"] as? String else { return }
        let minConf = (obj["minConfidence"] as? Double) ?? 0
        guard let candidate else {
            XCTFail("[\(label)] 抽出されなかった(期待: '\(value)')")
            return
        }
        XCTAssertEqual(candidate.value, value, "[\(label)] value")
        XCTAssertGreaterThanOrEqual(candidate.confidence, minConf, "[\(label)] confidence")
    }

    private func listCandidates(_ field: String, in r: ExtractionResult) -> [Candidate] {
        switch field {
        case "email": return r.email
        case "url": return r.url
        case "phone": return r.phone
        case "fax": return r.fax
        case "mobile": return r.mobile
        case "sns": return r.sns
        default: return []
        }
    }

    private func singleCandidate(_ field: String, in r: ExtractionResult) -> Candidate? {
        switch field {
        case "postalCode": return r.postalCode
        case "company": return r.company
        case "department": return r.department
        case "title": return r.title
        case "address": return r.address
        default: return nil
        }
    }
}
