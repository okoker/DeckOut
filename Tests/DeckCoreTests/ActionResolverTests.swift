import Foundation
import Testing
@testable import DeckCore

private func sampleConfig() throws -> AppConfig {
    try AppConfig.parse(Data("""
    { "decks": {
      "n3": { "brightness": 50,
              "buttons": { "lcd_1": { "action": "shell:open -a Notes" }, "lcd_2": { "action": "none" } },
              "knobs": { "big":     { "rotate": { "action": "system_volume", "step": 5 },
                                      "press":  { "action": "system_mute_toggle" } },
                         "small_1": { "rotate": { "action": "zr7_volume" },
                                      "press":  { "action": "none" } } } },
      "n4": { "brightness": 50,
              "keys": { "key_1": { "action": "shell:open -a Safari" } },
              "knobs": { "knob_2": { "rotate": { "action": "display_brightness", "step": 5 },
                                     "press":  { "action": "display_brightness_cycle" } } },
              "strip": { "2": { "type": "load", "action": "shell:open -a 'Activity Monitor'" },
                         "3": { "type": "empty" } },
              "swipe": { "action": "key:cmd+tab" } } } }
    """.utf8))
}

// MARK: - Resolution

@Test func n3KeyDownResolvesItsAction() throws {
    let c = try sampleConfig()
    #expect(ActionResolver.resolve(.keyDown("lcd_1"), deck: .n3, config: c)
            == ResolvedAction(action: "shell:open -a Notes", step: nil))
}

@Test func eachDeckReadsOnlyItsOwnSection() throws {
    let c = try sampleConfig()
    #expect(ActionResolver.resolve(.keyDown("key_1"), deck: .n3, config: c) == nil)
    #expect(ActionResolver.resolve(.keyDown("lcd_1"), deck: .n4, config: c) == nil)
    #expect(ActionResolver.resolve(.knobTurn("big", 1), deck: .n4, config: c) == nil)
}

@Test func knobTurnScalesStepBySign() throws {
    let c = try sampleConfig()
    #expect(ActionResolver.resolve(.knobTurn("knob_2", -1), deck: .n4, config: c)
            == ResolvedAction(action: "display_brightness", step: -5))
    #expect(ActionResolver.resolve(.knobTurn("knob_2", +1), deck: .n4, config: c)
            == ResolvedAction(action: "display_brightness", step: 5))
    // No `step` in the config: one unit per detent.
    #expect(ActionResolver.resolve(.knobTurn("small_1", -1), deck: .n3, config: c)
            == ResolvedAction(action: "zr7_volume", step: -1))
}

@Test func knobDownResolvesPressAction() throws {
    let c = try sampleConfig()
    #expect(ActionResolver.resolve(.knobDown("knob_2"), deck: .n4, config: c)
            == ResolvedAction(action: "display_brightness_cycle", step: nil))
}

@Test func stripTapAndSwipeResolve() throws {
    let c = try sampleConfig()
    #expect(ActionResolver.resolve(.stripTap("2"), deck: .n4, config: c)
            == ResolvedAction(action: "shell:open -a 'Activity Monitor'", step: nil))
    #expect(ActionResolver.resolve(.stripTap("3"), deck: .n4, config: c) == nil)   // block with no action
    #expect(ActionResolver.resolve(.swipe, deck: .n4, config: c)
            == ResolvedAction(action: "key:cmd+tab", step: nil))
    #expect(ActionResolver.resolve(.swipe, deck: .n3, config: c) == nil)
}

@Test func releasesNoneAndUnsetResolveToNothing() throws {
    let c = try sampleConfig()
    #expect(ActionResolver.resolve(.keyUp("lcd_1"), deck: .n3, config: c) == nil)
    #expect(ActionResolver.resolve(.knobUp("big"), deck: .n3, config: c) == nil)
    #expect(ActionResolver.resolve(.keyDown("lcd_2"), deck: .n3, config: c) == nil)     // "none"
    #expect(ActionResolver.resolve(.knobDown("small_1"), deck: .n3, config: c) == nil)  // "none"
    #expect(ActionResolver.resolve(.keyDown("lcd_6"), deck: .n3, config: c) == nil)     // not configured
}

// MARK: - Lock policy

@Test func lockedBlocksKeysTapsAndSwipe() {
    // Even a built-in action doesn't run from a key, tap or swipe while locked.
    #expect(!LockPolicy.allows(.keyDown("key_1"), action: "system_volume", locked: true))
    #expect(!LockPolicy.allows(.stripTap("4"), action: "system_mute_toggle", locked: true))
    #expect(!LockPolicy.allows(.swipe, action: "system_volume", locked: true))
}

@Test func lockedKnobsRunOnlyBuiltIns() {
    for action in ["system_volume", "zr7_volume", "display_brightness"] {
        #expect(LockPolicy.allows(.knobTurn("knob_4", -1), action: action, locked: true))
    }
    for action in ["system_mute_toggle", "zr7_mute_toggle", "display_brightness_cycle"] {
        #expect(LockPolicy.allows(.knobDown("knob_4"), action: action, locked: true))
    }
    #expect(!LockPolicy.allows(.knobTurn("big", 1), action: "shell:say hello", locked: true))
    #expect(!LockPolicy.allows(.knobDown("big"), action: "key:cmd+q", locked: true))
}

@Test func unlockedAllowsEverything() {
    let inputs: [DeckInput] = [.keyDown("key_1"), .knobTurn("knob_1", 1), .knobDown("knob_1"), .stripTap("1"), .swipe]
    for input in inputs {
        #expect(LockPolicy.allows(input, action: "shell:open -a Notes", locked: false))
        #expect(LockPolicy.allows(input, action: "key:cmd+space", locked: false))
    }
}

// MARK: - Steps on presses

@Test func pressesCarryTheirStep() throws {                         // T-084
    let c = try AppConfig.parse(Data("""
    { "decks": { "n4": { "brightness": 50,
      "keys": { "key_1": { "action": "system_volume", "step": 5 }, "key_2": { "action": "system_volume" } },
      "knobs": { "knob_1": { "rotate": { "action": "system_volume", "step": 5 },
                             "press":  { "action": "display_brightness", "step": -5 } } },
      "strip": { "1": { "type": "empty", "action": "system_volume", "step": -5 } },
      "swipe": { "action": "system_volume", "step": -5 } } } }
    """.utf8))
    #expect(ActionResolver.resolve(.keyDown("key_1"), deck: .n4, config: c) == ResolvedAction(action: "system_volume", step: 5))
    #expect(ActionResolver.resolve(.keyDown("key_2"), deck: .n4, config: c) == ResolvedAction(action: "system_volume", step: nil))
    #expect(ActionResolver.resolve(.knobDown("knob_1"), deck: .n4, config: c) == ResolvedAction(action: "display_brightness", step: -5))
    #expect(ActionResolver.resolve(.stripTap("1"), deck: .n4, config: c) == ResolvedAction(action: "system_volume", step: -5))
    #expect(ActionResolver.resolve(.swipe, deck: .n4, config: c) == ResolvedAction(action: "system_volume", step: -5))
}
