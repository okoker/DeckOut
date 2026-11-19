import SwiftUI

/// The DeckOut app. `DeckOut/main.swift` starts it.
public struct DeckOutApp: App {
    public init() {}

    public var body: some Scene {
        Window("DeckOut", id: "main") {
            Text("DeckOut")
                .frame(width: 946, height: 544)
        }
        .windowResizability(.contentSize)
    }
}
