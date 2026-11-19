import AppKit
import DeckCore
import Foundation

// One log line at a time, even when stdout is a file (launchd log): no block-buffered output.
setvbuf(stdout, nil, _IOLBF, 0)

// MARK: - Arguments
//   --config <path>   use this config file instead of searching for one (development)
//   --post-reload     ask a running daemon to re-read its config, then exit
//   --show-lock-photo keep the N4's lock photo up while unlocked (development: lining up the panel)

let arguments = CommandLine.arguments

if arguments.contains("--post-reload") {
    DistributedNotificationCenter.default().postNotificationName(
        .init(Daemon.reloadNotification), object: nil, userInfo: nil, deliverImmediately: true)
    print("Posted \(Daemon.reloadNotification)")
    exit(0)
}

// MARK: - Config path resolution

let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
let execDir = URL(fileURLWithPath: arguments[0])
    .deletingLastPathComponent().path

let candidates = [
    homeDir + "/.config/vsd/config.json",
    execDir + "/config.json"
]

let configPath: String
if let flag = arguments.firstIndex(of: "--config") {
    guard flag + 1 < arguments.count else {
        print("Error: --config needs a path")
        exit(1)
    }
    configPath = arguments[flag + 1]
} else if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
    configPath = found
} else {
    print("Error: config.json not found")
    print("Searched:")
    candidates.forEach { print("  \($0)") }
    exit(1)
}

// MARK: - Security checks

/// Validate config file security. Returns true if safe to load.
/// On startup (exitOnFail=true), exits the process on failure.
/// On SIGHUP reload (exitOnFail=false), returns false and keeps old config.
func validateConfigSecurity(_ path: String, exitOnFail: Bool) -> Bool {
    // Reject symlinks — lstat doesn't follow them, unlike stat/attributesOfItem
    var st = stat()
    guard lstat(path, &st) == 0 else {
        print("SECURITY: cannot stat config at \(path)")
        if exitOnFail { exit(1) }
        return false
    }
    if (st.st_mode & S_IFMT) == S_IFLNK {
        print("SECURITY: config is a symlink — refusing to load. Use a regular file.")
        if exitOnFail { exit(1) }
        return false
    }

    // Check ownership matches current user
    if st.st_uid != getuid() {
        print("SECURITY: config owned by uid \(st.st_uid), expected \(getuid()) — refusing to load.")
        if exitOnFail { exit(1) }
        return false
    }

    // Reject group/world-writable
    let posix = st.st_mode & 0o777
    if posix & 0o022 != 0 {
        print("SECURITY: config is group/world-writable (mode \(String(posix, radix: 8))) — refusing to load. Run: chmod 600 \(path)")
        if exitOnFail { exit(1) }
        return false
    }

    return true
}


// MARK: - Load configuration

func printButtons(_ buttons: [String: ButtonConfig], label: String) {
    print("  \(label) configured: \(buttons.count)")
    for (name, btn) in buttons.sorted(by: { $0.key < $1.key }) {
        let iconNote = btn.icon.map { " (icon: \($0))" } ?? ""
        print("    \(name): \(btn.action)\(iconNote)")
    }
}

func printKnobs(_ knobs: [String: KnobConfig]) {
    print("  Knobs configured:  \(knobs.count)")
    for (name, knob) in knobs.sorted(by: { $0.key < $1.key }) {
        let rotateStep = knob.rotate.step.map { ", step: \($0)" } ?? ""
        print("    \(name): rotate=\(knob.rotate.action)\(rotateStep), press=\(knob.press.action)")
    }
}

func loadAndPrintConfig() -> AppConfig? {
    guard let config = AppConfig.load(from: configPath) else { return nil }
    print("Config loaded from: \(configPath)")
    if let n3 = config.n3 {
        print(" N3:")
        print("  Brightness:        \(n3.brightness)")
        printButtons(n3.buttons, label: "Buttons")
        printKnobs(n3.knobs)
    }
    if let n4 = config.n4 {
        print(" N4:")
        print("  Brightness:        \(n4.brightness)")
        printButtons(n4.keys, label: "Keys")
        printKnobs(n4.knobs)
        print("  Strip blocks:      \(n4.strip.count)")
        for (name, block) in n4.strip.sorted(by: { $0.key < $1.key }) {
            let tap = block.action.map { ", tap=\($0)" } ?? ""
            print("    \(name): \(block.type.rawValue)\(tap)")
        }
        print("  Swipe:             \(n4.swipe?.action ?? "none")")
        print("  Lock photo:        \(n4.lockPhoto ?? "none")")
    }
    if let displays = config.displays, !displays.isEmpty {
        print("  Displays configured: \(displays.count)")
        for d in displays {
            print("    \(d.name): serial=\(d.serial)")
        }
    }
    return config
}

_ = validateConfigSecurity(configPath, exitOnFail: true)

guard let initialConfig = loadAndPrintConfig() else {
    print("Fatal: could not load config at startup")
    exit(1)
}
// MARK: - Start

let daemon = Daemon(config: initialConfig)
daemon.showLockPhotoAlways = arguments.contains("--show-lock-photo")
daemon.start()

/// Re-read the config through the same security checks; on any failure keep the previous one.
func reloadConfig(reason: String) {
    print("\nReloading config (\(reason))...")
    guard validateConfigSecurity(configPath, exitOnFail: false) else {
        print("Config reload blocked by security check — keeping previous config.")
        return
    }
    guard let newConfig = loadAndPrintConfig() else {
        print("Config reload failed — keeping previous config.")
        return
    }
    daemon.reload(newConfig)
    print("Config reloaded.")
}

// MARK: - Signal handling

signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
signal(SIGHUP, SIG_IGN)

let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
let sighupSource = DispatchSource.makeSignalSource(signal: SIGHUP, queue: .main)

sigintSource.setEventHandler {
    print("\nShutting down...")
    CFRunLoopStop(CFRunLoopGetMain())
}
sigtermSource.setEventHandler {
    print("\nShutting down...")
    CFRunLoopStop(CFRunLoopGetMain())
}
sighupSource.setEventHandler { reloadConfig(reason: "SIGHUP") }

sigintSource.resume()
sigtermSource.resume()
sighupSource.resume()

// Reload notification (posted by --post-reload, later by the config app). `.deliverImmediately`:
// the daemon is never the active app, and AppKit would otherwise hold the notification back.
final class ReloadObserver: NSObject {
    @objc func reload(_ note: Notification) { reloadConfig(reason: "notification") }
}
let reloadObserver = ReloadObserver()
DistributedNotificationCenter.default().addObserver(
    reloadObserver, selector: #selector(ReloadObserver.reload(_:)),
    name: .init(Daemon.reloadNotification), object: nil, suspensionBehavior: .deliverImmediately)

// Initialise AppKit for HUD overlay windows (no dock icon, no menu bar)
NSApplication.shared.setActivationPolicy(.accessory)
NSApp.finishLaunching()

print("StreamDeckController running. SIGHUP or --post-reload to reload config, Ctrl+C to stop.")

// Block on the run loop — IOKit HID reports only arrive while this is running
CFRunLoopRun()

print("StreamDeckController stopped.")
