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
                .task {
                    #if DEBUG
                    WindowSnapshot.scheduleIfAsked(model: model)
                    SelfTest.runIfAsked(model: model)
                    #endif
                    await model.launch()
                }
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        // The toolbar's buttons draw their own picture and name, so macOS's right-click Icon and Text / Icon Only
        // menu had nothing to switch: fixed, with the menu gone. Icon Only, because Icon and Text keeps an empty
        // label row under the buttons, which lifts them ~5 pt above the window's close / minimise / zoom buttons.
        .windowToolbarLabelStyle(fixed: .iconOnly)
        .commands {
            CommandGroup(replacing: .undoRedo) { UndoCommands(model: model) }
        }

        Settings {
            SettingsView(model: model)
        }

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
