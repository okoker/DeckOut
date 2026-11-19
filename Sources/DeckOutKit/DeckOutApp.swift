import SwiftUI

/// The DeckOut app. `DeckOut/main.swift` starts it.
public struct DeckOutApp: App {
    @StateObject private var model = AppModel()

    public init() {}

    public var body: some Scene {
        Window(model.identity?.appName ?? "DeckOut", id: "main") {
            Group {
                if let link = model.link {
                    DebugView(model: model, link: link)
                } else {
                    Text(model.locationProblem ?? "…").padding()
                }
            }
            .frame(width: 946, height: 544)
            .task { await model.launch() }
        }
        .windowResizability(.contentSize)
    }
}
