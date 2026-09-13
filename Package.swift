// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DevSweep",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.9.6"),
    ],
    targets: [
        .executableTarget(
            name: "DevSweep",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/DevSweep",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DevSweepTests",
            dependencies: ["DevSweep", .product(name: "Yams", package: "Yams")],
            path: "Tests/DevSweepTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
