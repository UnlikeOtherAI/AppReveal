// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AppReveal",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "AppReveal",
            targets: ["AppReveal"]
        ),
    ],
    targets: [
        .target(
            name: "AppReveal",
            path: "Sources/AppReveal",
            swiftSettings: [
                // Compile in the private-API tap path (IOHIDDigitizerEvent injection) for
                // debug builds only. Release builds have zero private API symbols — safe for
                // App Store review. Remove this line if you want to opt out of private APIs
                // entirely, even in debug builds.
                .define("APPREVEAL_PRIVATE_API_TAPS", .when(configuration: .debug))
            ]
        ),
        .testTarget(
            name: "AppRevealTests",
            dependencies: ["AppReveal"],
            path: "Tests/AppRevealTests"
        ),
    ]
)
