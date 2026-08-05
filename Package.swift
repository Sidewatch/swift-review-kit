// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ReviewKit",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "ReviewKit", targets: ["ReviewKit"]),
    ],
    targets: [
        .target(name: "ReviewKit", path: "Sources",
                swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),
        .testTarget(name: "ReviewKitTests", dependencies: ["ReviewKit"], path: "Tests"),
    ]
)
