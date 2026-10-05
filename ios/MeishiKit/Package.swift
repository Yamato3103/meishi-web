// swift-tools-version: 6.0
import PackageDescription

// MeishiKit: 名刺管理アプリのロジック層(Core / Data / Domain)。
// SwiftUIのアプリシェル(Feature層)は別のXcodeターゲットから本パッケージを利用する。
// macOSプラットフォームも宣言しているのは、CI / ローカルで `swift test` を
// シミュレータ無し・高速に回せるようにするため(純ロジックのユニットテスト用)。
let package = Package(
    name: "MeishiKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "MeishiKit", targets: ["MeishiKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "MeishiKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "MeishiKitTests",
            dependencies: ["MeishiKit"]
        )
    ]
)
