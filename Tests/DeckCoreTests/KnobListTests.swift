import Foundation
import Testing
@testable import DeckCore

// Knob lists on the N4 (docs/design/knob_lists.md): a list knob steps through its items as it turns, the strip block
// above it shows the pick, and a press of the knob or a tap of the block runs it.

private let wikipedia = ButtonConfig(action: "url:https://en.wikipedia.org", icon: "/icons/wikipedia.png")
private let github = ButtonConfig(action: "url:https://github.com", icon: "/icons/github.png")
private let bbc = ButtonConfig(action: "url:https://www.bbc.co.uk", icon: "/icons/bbc.png")
private let volumeKnob = KnobConfig(rotate: KnobAction(action: "system_volume", step: 5),
                                    press: KnobAction(action: "system_mute_toggle"))

/// An N4 whose live preset, Work, has a list on knob 1 and volume on knob 4.
private func listConfig(_ list: [ButtonConfig], strip: [String: StripBlockConfig] = [:]) -> AppConfig {
    AppConfig(n4: N4Section(brightness: 50, swipe: nil, lockPhoto: nil,
                            presets: [N4Preset(name: "Work", keys: [:], strip: strip,
                                               knobs: ["knob_1": KnobConfig(list: list), "knob_4": volumeKnob]),
                                      N4Preset(name: "Music", keys: [:], strip: [:])],
                            activePreset: "Work"))
}

@Test func picksWrapBothWays() {                                    // T-202
    var picks = KnobPicks()
    for _ in 0..<5 { picks.turn(.n4, preset: "Work", knob: "knob_1", by: 1, count: 5) }
    #expect(picks.pick(.n4, preset: "Work", knob: "knob_1", count: 5) == 0)
    #expect(picks.turn(.n4, preset: "Work", knob: "knob_1", by: -1, count: 5) == 4)
    var fast = KnobPicks()
    for _ in 0..<100 { fast.turn(.n4, preset: "Work", knob: "knob_1", by: 1, count: 5) }
    #expect(fast.pick(.n4, preset: "Work", knob: "knob_1", count: 5) == 0)
    #expect(fast.turn(.n4, preset: "Work", knob: "knob_1", by: 1, count: 0) == nil)
    #expect(fast.pick(.n4, preset: "Work", knob: "knob_1", count: 0) == nil)
}

@Test func picksSurviveAndClamp() {                                 // T-203
    var picks = KnobPicks()
    for _ in 0..<3 { picks.turn(.n4, preset: "Work", knob: "knob_1", by: 1, count: 5) }
    // Each preset keeps its own: a swipe away and back finds the pick where it was.
    #expect(picks.pick(.n4, preset: "Music", knob: "knob_1", count: 5) == 0)
    #expect(picks.pick(.n4, preset: "Work", knob: "knob_1", count: 5) == 3)
    // The list shrank below the pick (an edit): back to the first item.
    #expect(picks.pick(.n4, preset: "Work", knob: "knob_1", count: 3) == 0)
    #expect(picks.turn(.n4, preset: "Work", knob: "knob_1", by: 1, count: 3) == 1)
    // A renamed preset starts again at the first item.
    #expect(picks.pick(.n4, preset: "Work 2", knob: "knob_1", count: 5) == 0)
}

@Test func listInputsResolve() {                                    // T-204
    let config = listConfig([wikipedia, github, bbc])
    var picks = KnobPicks()
    picks.turn(.n4, preset: "Work", knob: "knob_1", by: 2, count: 3)
    func outcome(_ input: DeckInput, deck: DeckKind = .n4, in config: AppConfig = config) -> ListOutcome? {
        ActionResolver.listOutcome(input, deck: deck, config: config, picks: picks)
    }
    #expect(outcome(.knobTurn("knob_1", -1)) == .turn(knob: "knob_1", sign: -1))
    let bbcRun = ListOutcome.run(ResolvedAction(action: "url:https://www.bbc.co.uk", step: nil))
    #expect(outcome(.knobDown("knob_1")) == bbcRun)
    #expect(outcome(.stripTap("1")) == bbcRun)                       // the block above knob 1
    #expect(outcome(.stripTap("2")) == nil)                          // no list on knob 2: the usual path
    #expect(outcome(.knobTurn("knob_4", 1)) == nil)
    #expect(outcome(.knobDown("knob_4")) == nil)
    #expect(outcome(.keyDown("key_1")) == nil)
    #expect(outcome(.knobDown("knob_1"), in: listConfig([])) == .empty(knob: "knob_1"))
    #expect(outcome(.knobDown("knob_1"), in: listConfig([ButtonConfig(action: "none")])) == .empty(knob: "knob_1"))
    #expect(outcome(.knobDown("knob_1"), deck: .n3) == nil)
}

@Test func listBlockShowsThePick() {                                // T-205
    let slot = DeckModel.n4.stripSlots["1"]!
    var picks = KnobPicks()
    picks.turn(.n4, preset: "Work", knob: "knob_1", by: 2, count: 3)
    #expect(LayoutPlan.slots(model: .n4, config: listConfig([wikipedia, github, bbc]), picks: picks)[slot]
            == .picture("/icons/bbc.png"))
    #expect(LayoutPlan.slots(model: .n4, config: listConfig([wikipedia, github, bbc]))[slot]
            == .picture("/icons/wikipedia.png"))                     // no pick yet: the first item
    #expect(LayoutPlan.slots(model: .n4, config: listConfig([ButtonConfig(action: "url:https://example.com")]))[slot]
            == .blank)                                               // no icon
    #expect(LayoutPlan.slots(model: .n4, config: listConfig([]))[slot] == .blank)
    // A hand edit that sets block 1 too: the list wins.
    let both = listConfig([wikipedia], strip: ["1": StripBlockConfig(type: .internet)])
    #expect(LayoutPlan.slots(model: .n4, config: both)[slot] == .picture("/icons/wikipedia.png"))
}

@Test func lockedListDoesNothing() async {                          // T-206
    // Turning, pressing and tapping a list knob do nothing while the Mac is locked, whatever the pick is. Unlocked,
    // a press runs the pick the way a key press would: here next_preset, which goes to the agent.
    let config = listConfig([ButtonConfig(action: "next_preset"), github, bbc])
    for locked in [true, false] {
        nonisolated(unsafe) let daemon = Daemon(config: config, environment: ShellEnvironment(fixed: [:]),
                                                lockMonitor: LockMonitor(isLockedNow: { locked }))
        nonisolated(unsafe) var asked = 0
        nonisolated(unsafe) var changed = 0
        daemon.onNextPreset = { _ in asked += 1 }
        daemon.onPicksChanged = { changed += 1 }
        let afterTurn: Int? = await onMain { done in
            daemon.handle(.n4, .knobTurn("knob_1", 1))
            done(daemon.picks.pick(.n4, preset: "Work", knob: "knob_1", count: 3))
        }
        let afterBack: Int? = await onMain { done in
            daemon.handle(.n4, .knobTurn("knob_1", -1))
            daemon.handle(.n4, .knobDown("knob_1"))
            daemon.handle(.n4, .stripTap("1"))
            done(daemon.picks.pick(.n4, preset: "Work", knob: "knob_1", count: 3))
        }
        #expect(afterTurn == (locked ? 0 : 1), "locked: \(locked)")
        #expect(afterBack == 0, "locked: \(locked)")
        #expect(asked == (locked ? 0 : 2), "locked: \(locked)")
        #expect(changed == (locked ? 0 : 2), "locked: \(locked)")
    }
}
