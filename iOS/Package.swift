// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AppReveal",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "AppReveal",
            targets: ["AppReveal"]
        ),
        .library(
            name: "AppRevealClient",
            targets: ["AppRevealClient"]
        ),
    ],
    targets: [
        .target(
            name: "AppReveal",
            path: "Sources/AppReveal"
        ),
        .target(
            name: "AppRevealClient",
            path: "Sources/AppRevealClient"
        ),
        .testTarget(
            name: "AppRevealTests",
            dependencies: ["AppReveal"],
            path: "Tests/AppRevealTests"
        ),
    ]
)
