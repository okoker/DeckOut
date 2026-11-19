import DeckCore
import Foundation

/// Actions as a person reads them.
public enum ActionNames {

    /// What an action does, and on what: ("Open App", "Notes").
    public static func summary(_ action: String) -> (title: String, detail: String?) {
        let choice = ActionChoice(action: action, step: nil)
        let title = choice.kind(in: .key).title
        switch choice {
        case .openApp(let path): return (title, appName(path))
        case .openWebsite(let url): return (title, url)
        case .openFile(let path), .runScript(let path): return (title, (path as NSString).lastPathComponent)
        case .keyboardShortcut(let keys): return (title, shortcutSymbols(keys))
        case .runShortcut(let name): return (title, name)
        case .runCommand(let command): return (title, command)
        case .volume: return ("Volume", nil)
        case .monitorBrightness: return ("Monitor Brightness", nil)
        case .switchMonitor: return (title, "Which monitor the brightness knob sets")
        case .unknown(let raw): return ("Unknown action", raw)
        default: return (title, nil)
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
