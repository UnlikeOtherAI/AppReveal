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
        .library(name: "AppRevealClient", targets: ["AppRevealClient"]),
    ],
    targets: [
        .target(name: "AppReveal", path: "iOS/Sources/AppReveal"),
        .target(name: "AppRevealClient", path: "iOS/Sources/AppRevealClient"),
        .testTarget(name: "AppRevealTests", dependencies: ["AppReveal"], path: "iOS/Tests/AppRevealTests"),
    ]
)
