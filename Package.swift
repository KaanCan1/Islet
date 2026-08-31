// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Islet",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Islet",
            path: "Sources/Islet",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
