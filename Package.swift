// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swift-review-kit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ReviewKit", targets: ["ReviewKit"]),
        .library(name: "ChangeFacts", targets: ["ChangeFacts"]),
        .library(name: "BlastRadius", targets: ["BlastRadius"]),
    ],
    dependencies: [
        .package(path: "../swift-foundation-extensions"),
        .package(path: "../swift-sqlite-reader"),
    ],
    targets: [
        .target(name: "ReviewKit", dependencies: [.product(name: "ProcessRunner", package: "swift-foundation-extensions"),
                                                  .product(name: "FoundationExtensions", package: "swift-foundation-extensions")],
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "ChangeFacts", dependencies: [.product(name: "SQLiteReader", package: "swift-sqlite-reader")],
                resources: [.process("Localizable.xcstrings")], swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "BlastRadius", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "ReviewKitTests", dependencies: ["ReviewKit"]),
        .testTarget(name: "ChangeFactsTests", dependencies: ["ChangeFacts"], resources: [.copy("Fixtures")]),
        .testTarget(name: "BlastRadiusTests", dependencies: ["BlastRadius"]),
    ]
)
