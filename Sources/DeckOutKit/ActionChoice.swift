import DeckCore
import Foundation

/// Where an action sits: a key (or N3 button), a knob's turn or press, or a strip block's tap.
public enum ControlSlot: Equatable {
    case key, knobTurn, knobPress, stripTap
}

/// An action as a person picks it. Reads and writes the config's action strings and steps
/// (`docs/REQUIREMENTS.md` → Actions).
public enum ActionChoice: Equatable {
    case nothing
    case openApp(String)
    case openWebsite(String)
    case openFile(String)
    case keyboardShortcut(String)
    case runShortcut(String)
    case playPause, nextTrack, previousTrack
    /// On a key, press or tap: up (+) or down (−) by the step. On a knob turn: per click, the turn gives the sign.
    case volume(step: Int)
    case mute
    case monitorBrightness(step: Int)
    case switchMonitor
    case runScript(String)
    case runCommand(String)
    case zr7Volume(step: Int)
    case zr7Mute
    case unknown(String)

    /// The menu items. Volume and brightness are two items on a key (up, down) and one on a knob turn.
    public enum Kind: Equatable, CaseIterable {
        case nothing, openApp, openWebsite, openFile, keyboardShortcut, runShortcut, playPause, nextTrack, previousTrack
        case volumeUp, volumeDown, mute, brightnessUp, brightnessDown, switchMonitor, runScript, runCommand
        case volume, monitorBrightness, zr7Volume, zr7Mute, unknown

        public var title: String {
            switch self {
            case .nothing: return "Nothing"
            case .openApp: return "Open App"
            case .openWebsite: return "Open Website"
            case .openFile: return "Open File or Folder"
            case .keyboardShortcut: return "Keyboard Shortcut"
            case .runShortcut: return "Run a Shortcut"
            case .playPause: return "Play / Pause"
            case .nextTrack: return "Next Track"
            case .previousTrack: return "Previous Track"
            case .volumeUp: return "Volume Up"
            case .volumeDown: return "Volume Down"
            case .mute: return "Mute"
            case .brightnessUp: return "Monitor Brightness Up"
            case .brightnessDown: return "Monitor Brightness Down"
            case .switchMonitor: return "Switch Monitor"
            case .runScript: return "Run Script"
            case .runCommand: return "Run Command"
            case .volume: return "Volume"
            case .monitorBrightness: return "Monitor Brightness"
            case .zr7Volume: return "ZR7 Volume"
            case .zr7Mute: return "ZR7 Mute"
            case .unknown: return "Unknown"
            }
        }
    }

    // MARK: - Config strings

    public init(action: String, step: Int?) {
        func payload(_ prefix: String) -> String? {
            action.hasPrefix(prefix) ? String(action.dropFirst(prefix.count)) : nil
        }
        if action == "none" { self = .nothing; return }
        if let p = payload("app:") { self = .openApp(p); return }
        if let p = payload("url:") { self = .openWebsite(p); return }
        if let p = payload("open:") { self = .openFile(p); return }
        if let p = payload("key:") { self = .keyboardShortcut(p); return }
        if let p = payload("shortcut:") { self = .runShortcut(p); return }
        if let p = payload("script:") { self = .runScript(p); return }
        if let p = payload("shell:") { self = .runCommand(p); return }
        switch action {
        case "media_play_pause": self = .playPause
        case "media_next": self = .nextTrack
        case "media_previous": self = .previousTrack
        case "system_volume": self = .volume(step: step ?? 0)
        case "system_mute_toggle": self = .mute
        case "display_brightness": self = .monitorBrightness(step: step ?? 0)
        case "display_brightness_cycle": self = .switchMonitor
        case "zr7_volume": self = .zr7Volume(step: step ?? 0)
        case "zr7_mute_toggle": self = .zr7Mute
        default: self = .unknown(action)
        }
    }

    public var action: String {
        switch self {
        case .nothing: return "none"
        case .openApp(let p): return "app:" + p
        case .openWebsite(let u): return "url:" + u
        case .openFile(let p): return "open:" + p
        case .keyboardShortcut(let k): return "key:" + k
        case .runShortcut(let n): return "shortcut:" + n
        case .playPause: return "media_play_pause"
        case .nextTrack: return "media_next"
        case .previousTrack: return "media_previous"
        case .volume: return "system_volume"
        case .mute: return "system_mute_toggle"
        case .monitorBrightness: return "display_brightness"
        case .switchMonitor: return "display_brightness_cycle"
        case .runScript(let p): return "script:" + p
        case .runCommand(let c): return "shell:" + c
        case .zr7Volume: return "zr7_volume"
        case .zr7Mute: return "zr7_mute_toggle"
        case .unknown(let a): return a
        }
    }

    public var step: Int? {
        switch self {
        case .volume(let s), .monitorBrightness(let s), .zr7Volume(let s): return s
        default: return nil
        }
    }

    // MARK: - Menus

    public func kind(in slot: ControlSlot) -> Kind {
        switch self {
        case .nothing: return .nothing
        case .openApp: return .openApp
        case .openWebsite: return .openWebsite
        case .openFile: return .openFile
        case .keyboardShortcut: return .keyboardShortcut
        case .runShortcut: return .runShortcut
        case .playPause: return .playPause
        case .nextTrack: return .nextTrack
        case .previousTrack: return .previousTrack
        case .volume(let s): return slot == .knobTurn ? .volume : (s < 0 ? .volumeDown : .volumeUp)
        case .mute: return .mute
        case .monitorBrightness(let s): return slot == .knobTurn ? .monitorBrightness : (s < 0 ? .brightnessDown : .brightnessUp)
        case .switchMonitor: return .switchMonitor
        case .runScript: return .runScript
        case .runCommand: return .runCommand
        case .zr7Volume: return .zr7Volume
        case .zr7Mute: return .zr7Mute
        case .unknown: return .unknown
        }
    }

    /// The pop-up's items in groups (a separator between groups). Knob turns pass a step to every action, so they
    /// offer only the stepped ones; ZR7 is on no menu (a control already set to it shows it read-only).
    public static func menu(for slot: ControlSlot) -> [[Kind]] {
        switch slot {
        case .knobTurn:
            return [[.nothing], [.volume, .monitorBrightness]]
        case .key, .knobPress, .stripTap:
            return [[.nothing], [.openApp, .openWebsite, .openFile], [.keyboardShortcut, .runShortcut],
                    [.playPause, .nextTrack, .previousTrack], [.volumeUp, .volumeDown, .mute],
                    [.brightnessUp, .brightnessDown, .switchMonitor], [.runScript, .runCommand]]
        }
    }

    /// A fresh choice for a picked menu item: empty fields, sensible steps.
    public static func make(_ kind: Kind) -> ActionChoice {
        switch kind {
        case .nothing: return .nothing
        case .openApp: return .openApp("")
        case .openWebsite: return .openWebsite("https://")
        case .openFile: return .openFile("")
        case .keyboardShortcut: return .keyboardShortcut("")
        case .runShortcut: return .runShortcut("")
        case .playPause: return .playPause
        case .nextTrack: return .nextTrack
        case .previousTrack: return .previousTrack
        case .volumeUp: return .volume(step: 5)
        case .volumeDown: return .volume(step: -5)
        case .mute: return .mute
        case .brightnessUp: return .monitorBrightness(step: 10)
        case .brightnessDown: return .monitorBrightness(step: -10)
        case .switchMonitor: return .switchMonitor
        case .runScript: return .runScript("")
        case .runCommand: return .runCommand("")
        case .volume: return .volume(step: 2)
        case .monitorBrightness: return .monitorBrightness(step: 5)
        case .zr7Volume: return .zr7Volume(step: 2)
        case .zr7Mute: return .zr7Mute
        case .unknown: return .nothing
        }
    }

    /// Needs the agent allowed under Accessibility (it posts keyboard events).
    public var needsAccessibility: Bool {
        switch self {
        case .keyboardShortcut, .playPause, .nextTrack, .previousTrack: return true
        default: return false
        }
    }
}
