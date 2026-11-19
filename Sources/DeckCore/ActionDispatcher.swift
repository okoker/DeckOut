import AppKit
import ApplicationServices
import Foundation
import CoreGraphics

public final class ActionDispatcher {

    // MARK: - Properties

    private let config: AppConfig
    private let shellQueue = DispatchQueue(label: "streamdeck.shell", qos: .utility)
    private let environment: ShellEnvironment

    /// Owned by the `Daemon`, which keeps one across reloads and builds it off the main thread.
    /// Nil while it is being built (`brightnessBuilding`), or when no monitors are set up.
    var brightnessControl: BrightnessControl?
    var brightnessBuilding = false

    // MARK: - Key code tables

    private static let letterKeyCodes: [String: CGKeyCode] = [
        "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02, "e": 0x0E,
        "f": 0x03, "g": 0x05, "h": 0x04, "i": 0x22, "j": 0x26,
        "k": 0x28, "l": 0x25, "m": 0x2E, "n": 0x2D, "o": 0x1F,
        "p": 0x23, "q": 0x0C, "r": 0x0F, "s": 0x01, "t": 0x11,
        "u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07, "y": 0x10,
        "z": 0x06
    ]

    private static let numberKeyCodes: [String: CGKeyCode] = [
        "0": 0x1D, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15,
        "5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19
    ]

    private static let specialKeyCodes: [String: CGKeyCode] = [
        "space": 0x31,
        "return": 0x24, "enter": 0x24,
        "tab": 0x30,
        "escape": 0x35, "esc": 0x35,
        "delete": 0x33,
        "f1":  0x7A, "f2":  0x78, "f3":  0x63, "f4":  0x76,
        "f5":  0x60, "f6":  0x61, "f7":  0x62, "f8":  0x64,
        "f9":  0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
        "left": 0x7B, "right": 0x7C, "up": 0x7E, "down": 0x7D
    ]

    private static var allKeyCodes: [String: CGKeyCode] = {
        var combined = letterKeyCodes
        combined.merge(numberKeyCodes) { _, new in new }
        combined.merge(specialKeyCodes) { _, new in new }
        return combined
    }()

    // MARK: - Init

    init(config: AppConfig, brightness: BrightnessControl?, environment: ShellEnvironment) {
        self.config = config
        self.brightnessControl = brightness
        self.environment = environment

        // Warn once if key: or media actions are configured but Accessibility (needed to post events) is not granted
        var actions: [String] = []
        if let n3 = config.n3 {
            actions += n3.buttons.values.map(\.action)
            actions += n3.knobs.values.flatMap { [$0.rotate.action, $0.press.action] }
        }
        if let n4 = config.n4 {
            actions += n4.keys.values.map(\.action)
            actions += n4.knobs.values.flatMap { [$0.rotate.action, $0.press.action] }
            actions += n4.strip.values.compactMap(\.action)
            actions += [n4.swipe?.action].compactMap { $0 }
        }
        let needsAccessibility = actions.contains { $0.hasPrefix("key:") || MediaKey(rawValue: $0) != nil }
        if needsAccessibility && !AXIsProcessTrusted() {
            print("WARNING: key: or media actions configured but Accessibility is not granted. Keyboard shortcuts and media keys will silently fail. Grant access in System Settings → Privacy & Security → Accessibility.")
        }
    }

    // MARK: - Action execution

    /// Runs one action. `completion` gets what a command printed, or an error, for the config app's Test button;
    /// it may run on any queue. Programs run off the main thread; everything else runs here, at once.
    /// Call on the main thread.
    func execute(_ resolved: ResolvedAction, completion: ((ActionResult) -> Void)? = nil) {
        let done = completion ?? { _ in }
        switch ActionKind.parse(resolved.action) {
        case .none:
            done(ActionResult())
        case .shell(let command):
            // zsh -c, as always; with the user's own environment (PATH from their shell, not launchd's).
            runProgram("/bin/zsh", ["-c", command], label: "Shell", describing: command, done)
        case .script(let path):
            runProgram(path, [], label: "Script", describing: path, done)
        case .shortcut(let name):
            runProgram("/usr/bin/shortcuts", ["run", name], label: "Shortcut", describing: name, done)
        case .key(let shortcut):
            done(ActionResult(error: simulateKeyShortcut(shortcut) ?? accessibilityProblem()))
        case .media(let key):
            MediaKeys.post(key)
            done(ActionResult(error: accessibilityProblem()))
        case .app(let path):
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                               configuration: NSWorkspace.OpenConfiguration()) { _, error in
                let problem = error.map { "couldn't open \(path): \($0.localizedDescription)" }
                if let problem { print("Warning: \(problem)") }
                done(ActionResult(error: problem))
            }
        case .url(let url):
            done(ActionResult(error: open(url, describing: url.absoluteString)))
        case .open(let path):
            guard FileManager.default.fileExists(atPath: path) else {
                print("Warning: no file or folder at \(path)")
                done(ActionResult(error: "no file or folder at \(path)"))
                return
            }
            done(ActionResult(error: open(URL(fileURLWithPath: path), describing: path)))
        case .builtIn(let name):
            done(ActionResult(error: runBuiltIn(name, step: resolved.step)))
        case .invalid(let reason):
            print("Warning: \(reason)")
            done(ActionResult(error: reason))
        }
    }

    /// Runs a program off the main thread with the user's environment; arguments as an array, never a shell string.
    private func runProgram(_ executable: String, _ arguments: [String], label: String, describing: String,
                            _ done: @escaping (ActionResult) -> Void) {
        shellQueue.async { [environment] in
            let result = ProcessRunner.run(executable: executable, arguments: arguments, environment: environment.current)
            Self.log(result, label: label, command: describing)
            done(result)
        }
    }

    private func open(_ url: URL, describing: String) -> String? {
        guard NSWorkspace.shared.open(url) else {
            print("Warning: couldn't open \(describing)")
            return "couldn't open \(describing)"
        }
        return nil
    }

    /// Posting key and media events needs Accessibility; without it macOS drops them silently.
    private func accessibilityProblem() -> String? {
        AXIsProcessTrusted() ? nil : "needs Accessibility permission (System Settings → Privacy & Security → Accessibility)"
    }

    /// A press logs a failure, stderr and a non-zero exit. Stdout isn't logged: the Test button shows it.
    static func log(_ result: ActionResult, label: String, command: String) {
        if let error = result.error {
            print("\(label) failed (\(error)): \(command)")
        }
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            print("\(label) error: \(stderr)")
        }
        if let status = result.exitStatus, status != 0 {
            print("\(label) exit \(status): \(command)")
        }
    }

    /// The volume, mute, ZR7 and monitor-brightness actions. Returns a problem for the Test button, or nil.
    private func runBuiltIn(_ action: String, step: Int?) -> String? {
        if action == "system_volume" {
            let s = step ?? 0
            VolumeControl.adjust(step: s)
            return nil
        }

        if action == "system_mute_toggle" {
            VolumeControl.toggleMute()
            return nil
        }

        if action == "zr7_volume" {
            let s = step ?? 0
            let name = s >= 0 ? "com.zr7.volumeUp" : "com.zr7.volumeDown"
            DistributedNotificationCenter.default().postNotificationName(
                .init(name), object: nil, deliverImmediately: true)
            return nil
        }

        if action == "zr7_mute_toggle" {
            DistributedNotificationCenter.default().postNotificationName(
                .init("com.zr7.muteToggle"), object: nil, deliverImmediately: true)
            return nil
        }

        if action == "display_brightness" {
            guard let bc = brightnessControl else {
                let problem = brightnessBuilding ? "display_brightness: monitors not ready yet"
                                                 : "display_brightness action but no displays configured"
                print("Warning: \(problem)")
                return problem
            }
            bc.adjust(step: step ?? 0)
            return nil
        }

        if action == "display_brightness_cycle" {
            guard let bc = brightnessControl else {
                let problem = brightnessBuilding ? "display_brightness_cycle: monitors not ready yet"
                                                 : "display_brightness_cycle action but no displays configured"
                print("Warning: \(problem)")
                return problem
            }
            bc.cycleMode()
            return nil
        }

        print("Warning: unknown action '\(action)'")
        return "unknown action '\(action)'"
    }

    // MARK: - Key shortcut simulation

    /// Posts the shortcut. Returns what was wrong with it, or nil.
    private func simulateKeyShortcut(_ shortcut: String) -> String? {
        let parts = shortcut.lowercased().split(separator: "+").map(String.init)
        guard !parts.isEmpty else {
            print("Warning: empty key shortcut")
            return "empty key shortcut"
        }

        let keyName = parts.last!
        let modifierNames = parts.dropLast()

        guard let keyCode = Self.allKeyCodes[keyName] else {
            print("Warning: unknown key '\(keyName)' in shortcut '\(shortcut)'")
            return "unknown key '\(keyName)' in shortcut '\(shortcut)'"
        }

        var flags: CGEventFlags = []
        for mod in modifierNames {
            switch mod {
            case "cmd", "command":
                flags.insert(.maskCommand)
            case "shift":
                flags.insert(.maskShift)
            case "ctrl", "control":
                flags.insert(.maskControl)
            case "alt", "opt", "option":
                flags.insert(.maskAlternate)
            default:
                print("Warning: unknown modifier '\(mod)' in shortcut '\(shortcut)'")
            }
        }

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp   = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            print("Warning: could not create CGEvent for shortcut '\(shortcut)'")
            return "could not create the key event for '\(shortcut)'"
        }

        keyDown.flags = flags
        keyUp.flags   = flags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return nil
    }
}
