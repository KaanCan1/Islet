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
        ),
        // Tests import the app itself rather than a library split out of it:
        // SwiftPM lets a test target depend on an executable one.
        .testTarget(
            name: "IsletTests",
            dependencies: ["Islet"],
            path: "Tests/IsletTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
