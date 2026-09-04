// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ReviewKit",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../swift-process-runner"),
    ],
    products: [
        .library(name: "ReviewKit", targets: ["ReviewKit"]),
    ],
    targets: [
        .target(name: "ReviewKit", dependencies: [.product(name: "ProcessRunner", package: "swift-process-runner")], path: "Sources",
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "ReviewKitTests", dependencies: ["ReviewKit"], path: "Tests"),
    ]
)
