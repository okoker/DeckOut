// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StreamDeckController",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "DeckCore", path: "Sources/DeckCore"),
        .executableTarget(name: "StreamDeckController", dependencies: ["DeckCore"], path: "Sources/VSDDaemon"),
        .testTarget(name: "DeckCoreTests", dependencies: ["DeckCore"], path: "Tests/DeckCoreTests",
                    exclude: ["Fixtures"]),   // read by path from the tests
    ],
    swiftLanguageModes: [.v5]
)
