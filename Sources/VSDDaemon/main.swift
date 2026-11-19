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

// MARK: - Start

let agent = Agent(configPath: configPath)
agent.start(showLockPhoto: arguments.contains("--show-lock-photo"))

func requestReload(reason: String) {
    print("Reload requested (\(reason))")
    agent.externalReload()
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
