// swift-tools-version: 6.0
import PackageDescription

// DeckOut: the app (`DeckOut`, over `DeckOutKit`) and its background part (`DeckOutAgent`), sharing `DeckCore`.
// `make app` assembles them into DeckOut.app (see the Makefile).
let package = Package(
    name: "DeckOut",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "DeckCore", path: "Sources/DeckCore"),
        .executableTarget(name: "DeckOutAgent", dependencies: ["DeckCore"], path: "Sources/DeckOutAgent"),
        .target(name: "DeckOutKit", dependencies: ["DeckCore"], path: "Sources/DeckOutKit"),
        .executableTarget(name: "DeckOut", dependencies: ["DeckOutKit"], path: "Sources/DeckOut"),
        .testTarget(name: "DeckCoreTests", dependencies: ["DeckCore"], path: "Tests/DeckCoreTests",
                    exclude: ["Fixtures"]),   // read by path from the tests
        .testTarget(name: "DeckOutKitTests", dependencies: ["DeckOutKit"], path: "Tests/DeckOutKitTests"),
    ],
    swiftLanguageModes: [.v5]
)
