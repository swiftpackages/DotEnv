// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "DotEnv",
    products: [
        .library(
            name: "DotEnv",
            targets: ["DotEnv"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", "2.23.0"..."2.39.0"),
    ],
    targets: [
        .target(
            name: "DotEnv",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
            ]),
        .testTarget(
            name: "DotEnvTests",
            dependencies: ["DotEnv"],
            resources: [
                .copy("Resources"),
            ]),
    ]
)
