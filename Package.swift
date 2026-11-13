// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lumakey",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LumakeyCore", targets: ["LumakeyCore"]),
        .executable(name: "Lumakey", targets: ["Lumakey"]),
        .executable(name: "lumakey-mcp", targets: ["lumakey-mcp"]),
        .executable(name: "lumakey-check", targets: ["lumakey-check"])
    ],
    targets: [
        .target(
            name: "LumakeyCore",
            path: "Sources/LumakeyCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "Lumakey",
            dependencies: ["LumakeyCore"],
            path: "Sources/Lumakey",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "lumakey-mcp",
            dependencies: ["LumakeyCore"],
            path: "Sources/LumakeyMCP",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "lumakey-check",
            dependencies: ["LumakeyCore"],
            path: "Tests/LumakeyCheck",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
