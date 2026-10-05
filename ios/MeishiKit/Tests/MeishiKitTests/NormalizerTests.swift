import XCTest
@testable import MeishiKit

final class NormalizerTests: XCTestCase {

    func testEmailIsLowercasedAndTrimmed() {
        XCTAssertEqual(Normalizer.email("  Yamada@Sample.CO.JP "), "yamada@sample.co.jp")
    }

    func testEmailNilAndEmpty() {
        XCTAssertNil(Normalizer.email(nil))
        XCTAssertNil(Normalizer.email("   "))
    }

    func testEmailFullwidthNormalizedToHalfwidth() {
        // 全角英字を含むメール → NFKC で半角化されて小文字化される。
        XCTAssertEqual(Normalizer.email("ＹＡＭＡＤＡ@sample.jp"), "yamada@sample.jp")
    }

    func testCompanyKeyStripsJapaneseCorporateSuffix() {
        XCTAssertEqual(Normalizer.companyKey("株式会社サンプル商事"), "サンプル商事")
        XCTAssertEqual(Normalizer.companyKey("サンプル商事株式会社"), "サンプル商事")
        XCTAssertEqual(Normalizer.companyKey("(株)サンプル"), "サンプル")
    }

    func testCompanyKeyStripsEnglishCorporateSuffix() {
        XCTAssertEqual(Normalizer.companyKey("Sample Co., Ltd."), "Sample")
        XCTAssertEqual(Normalizer.companyKey("Sample Inc."), "Sample")
    }

    func testCompanyKeyNilWhenEmpty() {
        XCTAssertNil(Normalizer.companyKey("株式会社"))
        XCTAssertNil(Normalizer.companyKey(nil))
    }
}
