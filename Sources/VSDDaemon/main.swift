import AppKit
import DeckCore
import Foundation
// MARK: - Config path resolution

let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
let execDir = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent().path

let candidates = [
    homeDir + "/.config/vsd/config.json",
    execDir + "/config.json"
]

guard let configPath = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
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
var config = initialConfig

// MARK: - Start HID device

let hidDevice = HIDDevice(config: config)
var dispatcher = ActionDispatcher(config: config)

hidDevice.onEvent = { event in
    dispatcher.dispatch(event: event)
}

hidDevice.start()

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

// SIGHUP = reload config without restart (keep old config on error)
sighupSource.setEventHandler {
    print("\nReloading config...")
    guard validateConfigSecurity(configPath, exitOnFail: false) else {
        print("Config reload blocked by security check — keeping previous config.")
        return
    }
    if let newConfig = loadAndPrintConfig() {
        config = newConfig
        dispatcher.shutdown()
        dispatcher = ActionDispatcher(config: config)
        hidDevice.reloadConfig(config)
        print("Config reloaded. Send SIGHUP again to reload.")
    } else {
        print("Config reload failed — keeping previous config.")
    }
}

sigintSource.resume()
sigtermSource.resume()
sighupSource.resume()

// Initialise AppKit for HUD overlay windows (no dock icon, no menu bar)
NSApplication.shared.setActivationPolicy(.accessory)
NSApp.finishLaunching()

print("StreamDeckController running. SIGHUP to reload config, Ctrl+C to stop.")

// Block on the run loop — IOKit HID reports only arrive while this is running
CFRunLoopRun()

print("StreamDeckController stopped.")
