import AppKit
import SwiftUI

/// The DeckOut app. `DeckOut/main.swift` starts it.
public struct DeckOutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    public init() {}

    public var body: some Scene {
        Window(model.identity?.appName ?? "DeckOut", id: "main") {
            MainWindow(model: model)
                .task { await model.launch() }
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified(showsTitle: false))

        #if DEBUG
        Window("Agent Status", id: "agent-status") {
            if let link = model.link {
                DebugView(model: model, link: link).frame(width: 520, height: 420)
            }
        }
        #endif
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
