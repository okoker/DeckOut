import CoreGraphics
import Foundation

/// The keys a `key:` action can name, and their macOS key codes (US layout positions): the one table the agent
/// posts from and the app records with, so the app never saves a shortcut the agent can't send.
public enum KeyNames {

    private static let letters: [String: CGKeyCode] = [
        "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02, "e": 0x0E,
        "f": 0x03, "g": 0x05, "h": 0x04, "i": 0x22, "j": 0x26,
        "k": 0x28, "l": 0x25, "m": 0x2E, "n": 0x2D, "o": 0x1F,
        "p": 0x23, "q": 0x0C, "r": 0x0F, "s": 0x01, "t": 0x11,
        "u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07, "y": 0x10,
        "z": 0x06,
    ]

    private static let numbers: [String: CGKeyCode] = [
        "0": 0x1D, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15,
        "5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19,
    ]

    private static let specials: [String: CGKeyCode] = [
        "space": 0x31,
        "return": 0x24, "enter": 0x24,
        "tab": 0x30,
        "escape": 0x35, "esc": 0x35,
        "delete": 0x33,
        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76,
        "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64,
        "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
        "left": 0x7B, "right": 0x7C, "up": 0x7E, "down": 0x7D,
    ]

    private static let codes: [String: CGKeyCode] = letters.merging(numbers) { $1 }.merging(specials) { $1 }

    /// Aliases (`enter`, `esc`) read; recording writes the main name.
    private static let aliases: Set<String> = ["enter", "esc"]

    public static var allNames: [String] { codes.keys.sorted() }

    public static func keyCode(for name: String) -> CGKeyCode? { codes[name] }

    public static func name(forKeyCode code: UInt16) -> String? {
        codes.first { $0.value == CGKeyCode(code) && !aliases.contains($0.key) }?.key
    }

    /// "cmd+shift+4" for the key and modifiers pressed, or nil for a key a `key:` action can't name.
    public static func shortcut(keyCode: UInt16, command: Bool, shift: Bool, option: Bool, control: Bool) -> String? {
        guard let key = name(forKeyCode: keyCode) else { return nil }
        var parts: [String] = []
        if command { parts.append("cmd") }
        if control { parts.append("ctrl") }
        if option { parts.append("opt") }
        if shift { parts.append("shift") }
        parts.append(key)
        return parts.joined(separator: "+")
    }
}
