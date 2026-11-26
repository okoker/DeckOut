import Foundation

/// Which DeckOut this is, and every name that follows from it: the agent's launchd label (also its Mach service
/// and its signing identifier), the agent plist, the config file and the log folder. Both the app and the agent
/// read it from the bundle they run in (the agent is a helper inside the app bundle, so `Bundle.main` is the app).
///
/// The dev variant keeps its own config and logs, so testing it never touches the live setup.
public struct AppIdentity: Equatable {
    public let bundleID: String

    public static let release = AppIdentity(id: "io.github.okoker.deckout")
    public static let dev = AppIdentity(id: "io.github.okoker.deckout.dev")

    /// The helper executable inside `Contents/MacOS`.
    public static let helperName = "DeckOutAgent"

    private init(id: String) { bundleID = id }

    /// Nil for anything but the two DeckOut bundle ids (e.g. `com.streamdeck.controller`, the hand install of 1.0,
    /// from when the app was StreamDeckController, before it was renamed DeckOut).
    public init?(bundleID: String?) {
        switch bundleID {
        case AppIdentity.release.bundleID: self = .release
        case AppIdentity.dev.bundleID: self = .dev
        default: return nil
        }
    }

    /// The identity of the bundle this process runs in, if it is DeckOut.
    public static var current: AppIdentity? { AppIdentity(bundleID: Bundle.main.bundleIdentifier) }

    public var isDev: Bool { self == .dev }
    public var appName: String { isDev ? "DeckOut Dev" : "DeckOut" }
    public var agentLabel: String { bundleID + ".agent" }
    public var agentPlistName: String { agentLabel + ".plist" }

    /// `~/.deckout/config.json` (dev: `~/.deckout-dev/config.json`). 1.0 and DeckOut 2.0.0 used `~/.config/vsd`,
    /// from the app's first name (VSD Display Controller, then StreamDeckController, now DeckOut); nothing moves it.
    public func configPath(home: String) -> String {
        home + configFolderInHome + "/config.json"
    }

    /// The settings folder as messages name it: `~/.deckout` (dev: `~/.deckout-dev`).
    public var configFolderForPeople: String { "~" + configFolderInHome }

    private var configFolderInHome: String { isDev ? "/.deckout-dev" : "/.deckout" }

    public func logFolder(home: String) -> String {
        home + "/Library/Logs/" + appName
    }
}
