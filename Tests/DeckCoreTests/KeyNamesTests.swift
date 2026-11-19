import CoreGraphics
import Testing
@testable import DeckCore

@Test func recordsWhatTheDispatcherCanPost() {   // T-126
    #expect(KeyNames.shortcut(keyCode: 0x15, command: true, shift: true, option: false, control: false) == "cmd+shift+4")
    #expect(KeyNames.shortcut(keyCode: 0x60, command: false, shift: false, option: false, control: false) == "f5")
    #expect(KeyNames.shortcut(keyCode: 0x00, command: true, shift: false, option: true, control: true) == "cmd+ctrl+opt+a")
    // A key the dispatcher has no name for can't be recorded (it would silently do nothing).
    #expect(KeyNames.shortcut(keyCode: 0x7F, command: true, shift: false, option: false, control: false) == nil)
    #expect(KeyNames.shortcut(keyCode: 0x32, command: false, shift: false, option: false, control: false) == nil)   // ` on US
    // Aliases resolve; recording writes the main name.
    #expect(KeyNames.keyCode(for: "enter") == 0x24)
    #expect(KeyNames.name(forKeyCode: 0x24) == "return")
    #expect(KeyNames.name(forKeyCode: 0x35) == "escape")
    // Every name maps to a code that maps back to a name for the same key.
    for name in KeyNames.allNames {
        let code = KeyNames.keyCode(for: name)!
        #expect(KeyNames.keyCode(for: KeyNames.name(forKeyCode: UInt16(code))!) == code, "\(name)")
    }
}
