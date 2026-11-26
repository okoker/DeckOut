import Foundation

/// The hand-installed controller from before DeckOut (the README's v1.0.0 install, `com.streamdeck.controller`).
/// While it runs next to DeckOut's own, every press fires twice. DeckOut offers to retire it, only on a click:
/// launchd stops it and its plist moves aside (kept, so it can be put back); its program and config are left alone.
public enum OldController {
    public enum RetireError: Error { case stillRunning }
    /// 1.0's launchd label, from when the app was StreamDeckController (renamed DeckOut in 2.0). Keep it: it is how
    /// DeckOut finds a 1.0 install.
    public static let label = "com.streamdeck.controller"

    public static func plistPath(home: String) -> String {
        home + "/Library/LaunchAgents/\(label).plist"
    }

    /// The old controller's plist, if it is still installed.
    public static func find(home: String) -> String? {
        let path = plistPath(home: home)
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    /// Stops it by its plist (`launchctl bootout gui/<uid> <plist>`, the README's own form), checks launchd no longer
    /// has it (`launchctl print gui/<uid>/com.streamdeck.controller` fails), then moves the plist to
    /// `….plist.retired-by-deckout`. Still loaded → `RetireError.stillRunning`, and nothing is moved. Already
    /// retired (no plist): nothing happens, and the kept copy is left alone.
    public static func retire(home: String, uid: uid_t = getuid(),
                              launchctl: ([String]) -> Int32 = OldController.runLaunchctl) throws {
        let path = plistPath(home: home), retired = path + ".retired-by-deckout"
        guard FileManager.default.fileExists(atPath: path) else { return }
        _ = launchctl(["bootout", "gui/\(uid)", path])
        guard launchctl(["print", "gui/\(uid)/\(label)"]) != 0 else { throw RetireError.stillRunning }
        try? FileManager.default.removeItem(atPath: retired)
        try FileManager.default.moveItem(atPath: path, toPath: retired)
    }

    public static func runLaunchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
