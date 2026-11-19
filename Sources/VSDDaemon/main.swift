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

guard let configPath = ConfigFile.resolvePath(arguments: arguments, home: homeDir, execDir: execDir) else {
    print("Error: --config needs a path")
    exit(1)
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

/// "Preset: Music (2 presets)", and a warning when `active_preset` names no preset.
func printPreset(active: String, live: String, count: Int) {
    if active != live { print("  Warning: active_preset \"\(active)\" not found, using \"\(live)\"") }
    print("  Preset: \(live) (\(count) preset\(count == 1 ? "" : "s"))")
}

func printConfig(_ config: AppConfig) {
    print("Config loaded from: \(configPath)")
    if let n3 = config.n3 {
        print(" N3:")
        printPreset(active: n3.activePreset, live: n3.active.name, count: n3.presets.count)
        print("  Brightness:        \(n3.brightness)")
        printButtons(n3.buttons, label: "Buttons")
        printKnobs(n3.knobs)
    }
    if let n4 = config.n4 {
        print(" N4:")
        printPreset(active: n4.activePreset, live: n4.active.name, count: n4.presets.count)
        print("  Brightness:        \(n4.brightness)")
        printButtons(n4.keys, label: "Keys")
        printKnobs(n4.knobs)
        print("  Strip blocks:      \(n4.strip.count)")
        for (name, block) in n4.strip.sorted(by: { $0.key < $1.key }) {
            let tap = block.action.map { ", tap=\($0)" } ?? ""
            print("    \(name): \(block.type.rawValue)\(tap)")
        }
        print("  Swipe:             \(n4.swipe?.action ?? "none")")
        print("  Lock photo:        \(n4.lockPhoto.map { "\($0.path) (zoom \($0.zoom), offset \($0.offsetX), \($0.offsetY))" } ?? "none")")
    }
    if let displays = config.displays, !displays.isEmpty {
        print("  Displays configured: \(displays.count)")
        for d in displays {
            print("    \(d.name): serial=\(d.serial)")
        }
    }
}

// Without a usable config the daemon still runs, with the decks blank, and says why: under launchd's KeepAlive,
// exiting would restart it into the same failure forever. A reload that loads replaces the blank config.
let startup = ConfigFile.startupConfig(at: configPath)
if let problem = startup.problem {
    print(problem)
    print("Starting with no decks set up (they stay blank) until a reload loads a config.")
} else {
    printConfig(startup.config)
}

// MARK: - Start

let daemon = Daemon(config: startup.config)
daemon.start()
if arguments.contains("--show-lock-photo") { daemon.showLockPhoto(startup.config.n4?.lockPhoto) }

/// Re-read the config through the same security checks; on any failure keep the previous one.
func reloadConfig() -> ReloadResult {
    print("\nReloading config...")
    switch ConfigFile.load(at: configPath) {
    case .success(let newConfig):
        printConfig(newConfig)
        daemon.reload(newConfig)
        print("Config reloaded.")
        return ReloadResult(loaded: true, problem: nil)
    case .failure(let error):
        print("\(error.description) — keeping previous config.")
        return ReloadResult(loaded: false, problem: error.description)
    }
}

/// A burst of reload requests (a save per slider step) becomes one reload.
let reloadMerger = ReloadMerger { reloadConfig() }

func requestReload(reason: String) {
    print("Reload requested (\(reason))")
    reloadMerger.request(nil)
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
sighupSource.setEventHandler { requestReload(reason: "SIGHUP") }

sigintSource.resume()
sigtermSource.resume()
sighupSource.resume()

// Reload notification (posted by --post-reload, later by the config app). `.deliverImmediately`:
// the daemon is never the active app, and AppKit would otherwise hold the notification back.
final class ReloadObserver: NSObject {
    @objc func reload(_ note: Notification) { requestReload(reason: "notification") }
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
