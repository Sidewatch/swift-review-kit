// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ChangeFacts",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ChangeFacts", targets: ["ChangeFacts"]),
    ],
    dependencies: [
        .package(path: "../swift-sqlite-reader"),
    ],
    targets: [
        .target(name: "ChangeFacts", dependencies: [.product(name: "SQLiteReader", package: "swift-sqlite-reader")], path: "Sources",
                resources: [.process("ChangeFacts/Localizable.xcstrings")],
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "ChangeFactsTests", dependencies: ["ChangeFacts"], path: "Tests", resources: [.copy("ChangeFactsTests/Fixtures")]),
    ]
)
