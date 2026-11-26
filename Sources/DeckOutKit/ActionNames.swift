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
        if let list = knob.list { return "List of \(list.count)" }
        switch knob.rotate.action {
        case "none": return "—"
        case "system_volume": return "Volume"
        case "display_brightness": return "Brightness"
        case "zr7_volume": return "ZR7"
        default: return summary(knob.rotate.action).title
        }
    }

    /// A knob list item's name in its row: the site's host, the app's or file's name, else the action's title.
    public static func itemName(_ item: ButtonConfig) -> String {
        switch ActionChoice(action: item.action, step: item.step) {
        case .openWebsite(let url): return URL(string: url)?.host ?? url
        case .openApp, .openFile, .runScript: return summary(item.action).detail ?? item.action
        default: return summary(item.action).title
        }
    }

    /// `cmd+shift+4` → `⇧⌘4`: modifiers in the Mac's own order (⌃⌥⇧⌘), then the key.
    public static func shortcutSymbols(_ keys: String) -> String {
        let order: [(names: Set<String>, symbol: String)] = [
            (["ctrl", "control"], "⌃"), (["alt", "opt", "option"], "⌥"), (["shift"], "⇧"), (["cmd", "command"], "⌘"),
        ]
        let parts = keys.lowercased().split(separator: "+").map(String.init)
        guard let key = parts.last else { return "" }
        let modifiers = Set(parts.dropLast())
        let symbols = order.filter { !$0.names.isDisjoint(with: modifiers) }.map(\.symbol).joined()
        let keyLabel: String
        switch key {
        case "space": keyLabel = "Space"
        case "return", "enter": keyLabel = "↩"
        case "tab": keyLabel = "⇥"
        case "escape", "esc": keyLabel = "⎋"
        case "delete": keyLabel = "⌫"
        case "left": keyLabel = "←"
        case "right": keyLabel = "→"
        case "up": keyLabel = "↑"
        case "down": keyLabel = "↓"
        default: keyLabel = key.count == 1 ? key.uppercased() : key.uppercased()
        }
        return symbols + keyLabel
    }

    /// `/Applications/Notes.app` → `Notes`.
    public static func appName(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
