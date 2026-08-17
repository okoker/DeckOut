import ApplicationServices
import Foundation
import CoreGraphics

final class ActionDispatcher {

    // MARK: - Properties

    private let config: DeckConfig
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

    /// Modifier name -> (event flag, left-hand virtual keycode). The keycode is
    /// needed because a flagsChanged event still names the physical key.
    private static let modifierKeys: [String: (flag: CGEventFlags, keyCode: CGKeyCode)] = [
        "cmd":     (.maskCommand,   0x37),
        "command": (.maskCommand,   0x37),
        "shift":   (.maskShift,     0x38),
        "ctrl":    (.maskControl,   0x3B),
        "control": (.maskControl,   0x3B),
        "alt":     (.maskAlternate, 0x3A),
        "opt":     (.maskAlternate, 0x3A),
        "option":  (.maskAlternate, 0x3A)
    ]

    // MARK: - Held modifier chord state

    private typealias Modifier = (flag: CGEventFlags, keyCode: CGKeyCode)

    /// The button currently holding a bare modifier chord down, if any.
    private var heldChord: (button: ButtonID, modifiers: [Modifier])?

    /// Failsafe release. A dropped buttonRelease packet would otherwise leave
    /// modifiers latched down system-wide, which is close to unrecoverable
    /// without killing the daemon.
    private var chordWatchdog: DispatchWorkItem?
    private static let chordHoldLimit: TimeInterval = 30

    // MARK: - Init

    init(config: DeckConfig) {
        self.config = config
        if let displays = config.displays, !displays.isEmpty {
            self.brightnessControl = BrightnessControl(displays: displays)
        } else {
            self.brightnessControl = nil
        }

        // Warn once if key: actions are configured but Input Monitoring is not granted
        let hasKeyActions = config.buttons.values.contains { $0.action.hasPrefix("key:") }
            || config.knobs.values.contains { $0.rotate.action.hasPrefix("key:") || $0.press.action.hasPrefix("key:") }
        // CGEvent.post(tap:) needs Accessibility, not Input Monitoring — Input
        // Monitoring gates *listening* to input, which this daemon never does.
        if hasKeyActions && !AXIsProcessTrusted() {
            print("WARNING: key: actions configured but Accessibility not granted. Keyboard shortcuts will silently fail. Grant access in System Settings → Privacy & Security → Accessibility.")
        }
    }

    /// Graceful teardown before replacement on config reload.
    func shutdown() {
        // Must come first: a chord still held here would stay latched
        // system-wide after this dispatcher is discarded.
        releaseHeldModifiers()
        brightnessControl?.shutdown()
    }

    // MARK: - Public dispatch

    func dispatch(event: DeckEvent) {
        print("Event: \(event)")
        switch event {

        // Button events
        case .buttonPress(let id):
            guard let buttonConfig = config.buttons[id.configKey] else {
                print("Warning: no config for button \(id.configKey)")
                return
            }
            // A key: action naming only modifiers is held for as long as the
            // deck button is held, rather than fired once on press.
            if buttonConfig.action.hasPrefix("key:"),
               let mods = Self.parseModifierOnly(String(buttonConfig.action.dropFirst("key:".count))) {
                holdModifiers(mods, for: id)
                return
            }
            execute(action: buttonConfig.action, step: nil)

        case .buttonRelease(let id):
            if heldChord?.button == id {
                releaseHeldModifiers()
            }
            return

        // Knob rotation
        case .knobRotateCW(let id):
            guard let knobConfig = config.knobs[id.configKey] else {
                print("Warning: no config for knob \(id.configKey)")
                return
            }
            let step = knobConfig.rotate.step ?? 1
            execute(action: knobConfig.rotate.action, step: +step)

        case .knobRotateCCW(let id):
            guard let knobConfig = config.knobs[id.configKey] else {
                print("Warning: no config for knob \(id.configKey)")
                return
            }
            let step = knobConfig.rotate.step ?? 1
            execute(action: knobConfig.rotate.action, step: -step)

        // Knob press
        case .knobPress(let id):
            guard let knobConfig = config.knobs[id.configKey] else {
                print("Warning: no config for knob \(id.configKey)")
                return
            }
            execute(action: knobConfig.press.action, step: nil)

        case .knobRelease:
            return
        }
    }

    // MARK: - Action execution

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

    // MARK: - Bare modifier chords (press-and-hold)

    /// Returns the modifiers if `spec` names only modifiers ("ctrl+shift"),
    /// or nil if it contains a real key and should be sent as a shortcut.
    private static func parseModifierOnly(_ spec: String) -> [Modifier]? {
        let parts = spec.lowercased().split(separator: "+").map(String.init)
        guard !parts.isEmpty else { return nil }
        var mods: [Modifier] = []
        for part in parts {
            guard let mod = modifierKeys[part] else { return nil }
            mods.append(mod)
        }
        return mods
    }

    /// Posts a flagsChanged event carrying the modifier state after this change.
    private func postFlagsChanged(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else {
            print("Warning: could not create flagsChanged event for keycode \(keyCode)")
            return
        }
        event.type = .flagsChanged
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private func holdModifiers(_ modifiers: [Modifier], for button: ButtonID) {
        // Never stack two chords — drop any previous hold first.
        if heldChord != nil { releaseHeldModifiers() }

        // Press one at a time, each event carrying the cumulative flags, the
        // way real hardware reports a chord being built up.
        var flags: CGEventFlags = []
        for mod in modifiers {
            flags.insert(mod.flag)
            postFlagsChanged(keyCode: mod.keyCode, flags: flags)
        }
        heldChord = (button, modifiers)

        let watchdog = DispatchWorkItem { [weak self] in
            guard let self, self.heldChord != nil else { return }
            print("Warning: modifier chord held past \(Int(Self.chordHoldLimit))s — releasing (missed button release?)")
            self.releaseHeldModifiers()
        }
        chordWatchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.chordHoldLimit, execute: watchdog)
    }

    private func releaseHeldModifiers() {
        chordWatchdog?.cancel()
        chordWatchdog = nil
        guard let held = heldChord else { return }
        heldChord = nil

        // Unwind in reverse, each event carrying what remains held.
        var flags: CGEventFlags = []
        for mod in held.modifiers { flags.insert(mod.flag) }
        for mod in held.modifiers.reversed() {
            flags.remove(mod.flag)
            postFlagsChanged(keyCode: mod.keyCode, flags: flags)
        }
    }
}
