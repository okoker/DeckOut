import Foundation

/// What an action string from the config asks for. Parsing checks the payload, so a bad one is reported (in the
/// log, and by the config app's Test button) instead of failing silently when pressed.
///
/// | String | Kind |
/// |---|---|
/// | `none` | nothing |
/// | `shell:<command>` | a command for `/bin/zsh -c` |
/// | `key:<shortcut>` | a keyboard shortcut, e.g. `cmd+shift+4` |
/// | `app:<path>` | open an app: an absolute path ending `.app` |
/// | `url:<URL>` | open a web address in the default browser: `http` or `https` with a host |
/// | `open:<path>` | open a file or folder: an absolute path |
/// | `script:<path>` | run a program or script directly: an absolute path |
/// | `shortcut:<name>` | run one of Apple's Shortcuts by name |
/// | `media_play_pause`, `media_next`, `media_previous` | the Mac's media keys |
/// | the built-ins (`LockPolicy.builtIns`) | volume, mute, ZR7, monitor brightness |
enum ActionKind: Equatable {
    case none
    case shell(String)
    case key(String)
    case app(String)
    case url(URL)
    case open(String)
    case script(String)
    case shortcut(String)
    case builtIn(String)
    case media(MediaKey)
    case invalid(String)    // why

    static func parse(_ action: String) -> ActionKind {
        func payload(_ prefix: String) -> String? {
            action.hasPrefix(prefix) ? String(action.dropFirst(prefix.count)) : nil
        }
        if action == "none" { return .none }
        if let command = payload("shell:") { return .shell(command) }
        if let shortcut = payload("key:") { return .key(shortcut) }
        if let path = payload("app:") {
            return path.hasPrefix("/") && path.hasSuffix(".app")
                ? .app(path) : .invalid("app: needs the full path to an app, like /Applications/Notes.app (got \"\(path)\")")
        }
        if let text = payload("url:") {
            guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  let host = url.host, !host.isEmpty else {
                return .invalid("url: needs a full web address starting with http:// or https:// (got \"\(text)\")")
            }
            return .url(url)
        }
        if let path = payload("open:") {
            return path.hasPrefix("/") ? .open(path) : .invalid("open: needs a full path, starting with / (got \"\(path)\")")
        }
        if let path = payload("script:") {
            return path.hasPrefix("/") ? .script(path) : .invalid("script: needs a full path, starting with / (got \"\(path)\")")
        }
        if let name = payload("shortcut:") {
            return name.trimmingCharacters(in: .whitespaces).isEmpty ? .invalid("shortcut: needs the Shortcut's name") : .shortcut(name)
        }
        if LockPolicy.builtIns.contains(action) { return .builtIn(action) }
        if let key = MediaKey(rawValue: action) { return .media(key) }
        return .invalid("unknown action '\(action)'")
    }
}
