import DeckCore
import Testing
@testable import DeckOutKit

@Test func roundTripsEveryKind() {   // T-125
    let choices: [ActionChoice] = [
        .nothing, .openApp("/Applications/Notes.app"), .openWebsite("https://example.com/a?b=c"),
        .openFile("/Users/x/Documents/a file.pdf"), .keyboardShortcut("cmd+shift+4"), .runShortcut("Show Notification"),
        .playPause, .nextTrack, .previousTrack, .volume(step: 5), .volume(step: -5), .mute,
        .monitorBrightness(step: 10), .monitorBrightness(step: -10), .switchMonitor,
        .runScript("/Users/x/bin/go.sh"), .runCommand("open -a 'Google Chrome'"), .zr7Volume(step: 2), .zr7Mute,
        .unknown("teleport"),
    ]
    for choice in choices {
        #expect(ActionChoice(action: choice.action, step: choice.step) == choice, "\(choice)")
    }
    // Strings from today's live config read as what they are.
    #expect(ActionChoice(action: "shell:open -a 'Google Chrome'", step: nil) == .runCommand("open -a 'Google Chrome'"))
    #expect(ActionChoice(action: "system_volume", step: 5) == .volume(step: 5))
    #expect(ActionChoice(action: "display_brightness", step: nil) == .monitorBrightness(step: 0))
    #expect(ActionChoice.nothing.action == "none")
    #expect(ActionChoice.volume(step: -5).step == -5)
    #expect(ActionChoice.playPause.step == nil)
}

@Test func menusFitTheControl() {   // T-125
    let turn = ActionChoice.menu(for: .knobTurn).flatMap { $0 }
    #expect(turn == [.nothing, .volume, .monitorBrightness])
    let key = ActionChoice.menu(for: .key).flatMap { $0 }
    #expect(key.contains(.volumeUp) && key.contains(.volumeDown) && key.contains(.openApp) && key.contains(.runCommand))
    #expect(!key.contains(.volume))
    #expect(ActionChoice.menu(for: .knobPress) == ActionChoice.menu(for: .key))
    #expect(ActionChoice.menu(for: .stripTap) == ActionChoice.menu(for: .key))
    // ZR7 is on no menu.
    for slot in [ControlSlot.key, .knobTurn, .knobPress, .stripTap] {
        #expect(!ActionChoice.menu(for: slot).flatMap { $0 }.contains { $0 == .zr7Volume || $0 == .zr7Mute })
    }
    // Which item a choice shows as depends on where it is.
    #expect(ActionChoice.volume(step: -5).kind(in: .key) == .volumeDown)
    #expect(ActionChoice.volume(step: 2).kind(in: .knobTurn) == .volume)
    #expect(ActionChoice.zr7Volume(step: 2).kind(in: .knobTurn) == .zr7Volume)
    // Picking an item gives a sensible new choice.
    #expect(ActionChoice.make(.volumeDown) == .volume(step: -5))
    #expect(ActionChoice.make(.volume) == .volume(step: 2))
    #expect(ActionChoice.make(.openWebsite) == .openWebsite("https://"))
}

@Test func actionCheckSaysWhatsWrong() {   // T-125
    #expect(ActionCheck.problem("url:https://example.com") == nil)
    #expect(ActionCheck.problem("url:example.com") != nil)
    #expect(ActionCheck.problem("app:Notes") != nil)
    #expect(ActionCheck.problem("none") == nil)
}

@Test func problemsReadPlainly() {   // T-125
    #expect(ActionFields.plain("url: needs a full web address") == "Needs a full web address")
    #expect(ActionFields.plain("unknown action 'x'") == "Unknown action 'x'")
}
