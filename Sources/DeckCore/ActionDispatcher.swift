import ApplicationServices
import Foundation
import CoreGraphics

public final class ActionDispatcher {

    // MARK: - Properties

    private let config: AppConfig
    private let shellQueue = DispatchQueue(label: "streamdeck.shell", qos: .utility)
    private let brightnessControl: BrightnessControl?

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

    public init(config: AppConfig) {
        self.config = config
        if let displays = config.displays, !displays.isEmpty {
            self.brightnessControl = BrightnessControl(displays: displays)
        } else {
            self.brightnessControl = nil
        }

        // Warn once if key: actions are configured but Input Monitoring is not granted
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
        let hasKeyActions = actions.contains { $0.hasPrefix("key:") }
        if hasKeyActions && !AXIsProcessTrusted() {
            print("WARNING: key: actions configured but Input Monitoring not granted. Keyboard shortcuts will silently fail. Grant access in System Settings → Privacy & Security → Input Monitoring.")
        }
    }

    /// Graceful teardown before replacement on config reload.
    public func shutdown() {
        brightnessControl?.shutdown()
    }

    // MARK: - Action execution

    func execute(_ resolved: ResolvedAction) {
        execute(action: resolved.action, step: resolved.step)
    }

    private func execute(action: String, step: Int?) {
        if action == "none" {
            return
        }

        if action.hasPrefix("shell:") {
            let cmd = String(action.dropFirst("shell:".count))
            shellQueue.async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", cmd]
                let errPipe = Pipe()
                process.standardError = errPipe
                // Drain stderr on a dedicated queue to avoid pipe buffer deadlock.
                let errQueue = DispatchQueue(label: "streamdeck.shell.stderr")
                var errData = Data()
                errPipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    errQueue.sync { errData.append(chunk) }
                }
                do {
                    try process.run()
                } catch {
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    print("Shell launch failed: \(error)")
                    return
                }

                // Kill after 30 s to prevent a hung command from blocking the queue
                let timeout = DispatchWorkItem {
                    if process.isRunning {
                        print("Shell timeout (30s), killing: \(cmd)")
                        process.terminate()
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeout)

                process.waitUntilExit()
                timeout.cancel()
                errPipe.fileHandleForReading.readabilityHandler = nil
                let finalErr = errQueue.sync { errData }
                if let err = String(data: finalErr, encoding: .utf8), !err.isEmpty {
                    print("Shell error: \(err.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
                if process.terminationStatus != 0 {
                    print("Shell exit \(process.terminationStatus): \(cmd)")
                }
            }
            return
        }

        if action.hasPrefix("key:") {
            let shortcut = String(action.dropFirst("key:".count))
            simulateKeyShortcut(shortcut)
            return
        }

        if action == "system_volume" {
            let s = step ?? 0
            VolumeControl.adjust(step: s)
            return
        }

        if action == "system_mute_toggle" {
            VolumeControl.toggleMute()
            return
        }

        if action == "zr7_volume" {
            let s = step ?? 0
            let name = s >= 0 ? "com.zr7.volumeUp" : "com.zr7.volumeDown"
            DistributedNotificationCenter.default().postNotificationName(
                .init(name), object: nil, deliverImmediately: true)
            return
        }

        if action == "zr7_mute_toggle" {
            DistributedNotificationCenter.default().postNotificationName(
                .init("com.zr7.muteToggle"), object: nil, deliverImmediately: true)
            return
        }

        if action == "display_brightness" {
            guard let bc = brightnessControl else {
                print("Warning: display_brightness action but no displays configured")
                return
            }
            bc.adjust(step: step ?? 0)
            return
        }

        if action == "display_brightness_cycle" {
            guard let bc = brightnessControl else {
                print("Warning: display_brightness_cycle action but no displays configured")
                return
            }
            bc.cycleMode()
            return
        }

        print("Warning: unknown action '\(action)'")
    }

    // MARK: - Key shortcut simulation

    private func simulateKeyShortcut(_ shortcut: String) {
        let parts = shortcut.lowercased().split(separator: "+").map(String.init)
        guard !parts.isEmpty else {
            print("Warning: empty key shortcut")
            return
        }

        let keyName = parts.last!
        let modifierNames = parts.dropLast()

        guard let keyCode = Self.allKeyCodes[keyName] else {
            print("Warning: unknown key '\(keyName)' in shortcut '\(shortcut)'")
            return
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
            return
        }

        keyDown.flags = flags
        keyUp.flags   = flags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
