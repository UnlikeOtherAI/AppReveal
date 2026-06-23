// swift-tools-version: 5.9
// Root Package.swift — re-exports the iOS/macOS SPM package from the iOS/ subdirectory.

import PackageDescription

let package = Package(
    name: "AppReveal",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "AppReveal", targets: ["AppReveal"]),
    ],
    targets: [
        .target(
            name: "AppReveal",
            path: "iOS/Sources/AppReveal",
            swiftSettings: [
                .define("APPREVEAL_PRIVATE_API_TAPS", .when(configuration: .debug))
            ]
        ),
        .testTarget(name: "AppRevealTests", dependencies: ["AppReveal"], path: "iOS/Tests/AppRevealTests"),
    ]
)
