// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ReviewKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ReviewKit", targets: ["ReviewKit"]),
    ],
    dependencies: [
        .package(path: "../swift-process-runner"),
    ],
    targets: [
        .target(name: "ReviewKit", dependencies: [.product(name: "ProcessRunner", package: "swift-process-runner")], path: "Sources",
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "ReviewKitTests", dependencies: ["ReviewKit"], path: "Tests"),
    ]
)
