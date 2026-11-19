import DeckCore
import Foundation

/// Actions as a person reads them.
public enum ActionNames {

    /// What an action does, and on what: ("Open App", "Notes").
    public static func summary(_ action: String) -> (title: String, detail: String?) {
        func payload(_ prefix: String) -> String? {
            action.hasPrefix(prefix) ? String(action.dropFirst(prefix.count)) : nil
        }
        if action == "none" { return ("Nothing", nil) }
        if let command = payload("shell:") { return ("Run Command", command) }
        if let keys = payload("key:") { return ("Keyboard Shortcut", shortcutSymbols(keys)) }
        if let path = payload("app:") { return ("Open App", appName(path)) }
        if let url = payload("url:") { return ("Open Website", url) }
        if let path = payload("open:") { return ("Open File or Folder", (path as NSString).lastPathComponent) }
        if let path = payload("script:") { return ("Run Script", (path as NSString).lastPathComponent) }
        if let name = payload("shortcut:") { return ("Run a Shortcut", name) }
        switch action {
        case "media_play_pause": return ("Play / Pause", nil)
        case "media_next": return ("Next Track", nil)
        case "media_previous": return ("Previous Track", nil)
        case "system_volume": return ("Volume", nil)
        case "system_mute_toggle": return ("Mute", nil)
        case "display_brightness": return ("Monitor Brightness", nil)
        case "display_brightness_cycle": return ("Switch Monitor", "Which monitor the brightness knob sets")
        case "zr7_volume": return ("ZR7 Volume", nil)
        case "zr7_mute_toggle": return ("ZR7 Mute", nil)
        default: return ("Unknown action", action)
        }
    }

    /// A knob's caption under it in the drawing: what turning it does.
    public static func knobCaption(_ knob: KnobConfig) -> String {
        switch knob.rotate.action {
        case "none": return "—"
        case "system_volume": return "Volume"
        case "display_brightness": return "Brightness"
        case "zr7_volume": return "ZR7"
        default: return summary(knob.rotate.action).title
        }
    }

    /// `cmd+shift+4` → `⌘⇧4`.
    public static func shortcutSymbols(_ keys: String) -> String {
        let symbols = ["cmd": "⌘", "command": "⌘", "shift": "⇧", "alt": "⌥", "opt": "⌥", "option": "⌥",
                       "ctrl": "⌃", "control": "⌃"]
        return keys.lowercased().split(separator: "+").map { part in
            symbols[String(part)] ?? (part.count == 1 ? part.uppercased() : part.capitalized)
        }.joined()
    }

    /// `/Applications/Notes.app` → `Notes`.
    public static func appName(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
