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

    /// Nil for anything but the two DeckOut bundle ids (e.g. the hand-installed `com.streamdeck.controller`).
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

    public func configPath(home: String) -> String {
        home + (isDev ? "/.config/vsd-dev/config.json" : "/.config/vsd/config.json")
    }

    public func logFolder(home: String) -> String {
        home + "/Library/Logs/" + appName
    }
}
