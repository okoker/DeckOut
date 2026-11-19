import DeckCore
import Foundation

/// DeckOut registers its background part from inside its own bundle, so it must run from where it will stay:
/// `/Applications/DeckOut.app`. Opened from Downloads (or a disk image), macOS runs a translocated copy from a random
/// folder that disappears, and the registered agent would point at nothing. The dev variant may run from anywhere.
public enum AppLocation {
    public static let expectedPath = "/Applications/DeckOut.app"

    /// What's wrong with where the app is, or nil when it's in the right place.
    public static func problem(bundlePath: String, identity: AppIdentity) -> String? {
        if identity.isDev { return nil }
        let path = bundlePath.hasSuffix("/") ? String(bundlePath.dropLast()) : bundlePath
        guard path == expectedPath else {
            return "DeckOut needs to be in your Applications folder. Drag it there, then open it again."
        }
        return nil
    }
}
