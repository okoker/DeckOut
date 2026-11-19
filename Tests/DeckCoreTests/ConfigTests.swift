import Foundation
import Testing
@testable import DeckCore

private func parse(_ json: String) throws -> AppConfig {
    try AppConfig.parse(Data(json.utf8))
}

@Test func newFormatParses() throws {
    let c = try parse("""
    {
      "displays": [ { "name": "Left", "serial": "S1" } ],
      "decks": {
        "n3": {
          "brightness": 40,
          "buttons": { "lcd_1": { "action": "shell:open -a Notes" } },
          "knobs": { "big": { "rotate": { "action": "system_volume", "step": 5 },
                              "press":  { "action": "system_mute_toggle" } } }
        },
        "n4": {
          "brightness": 60,
          "keys": { "key_1": { "action": "shell:open -a Notes", "icon": "/tmp/notes.icns" } },
          "knobs": { "knob_1": { "rotate": { "action": "system_volume", "step": 5 },
                                 "press":  { "action": "system_mute_toggle" } } },
          "strip": {
            "1": { "type": "internet", "host": "example.net", "arrow_ms": 4, "timeout_s": 5,
                   "action": "shell:open -a Terminal" },
            "2": { "type": "load", "action": "shell:open -a 'Activity Monitor'" },
            "3": { "type": "empty" },
            "4": { "type": "volume" }
          },
          "swipe": { "action": "key:cmd+tab" },
          "lock_photo": "/tmp/photo.jpg"
        }
      }
    }
    """)
    #expect(c.displays?.first?.serial == "S1")

    let n3 = try #require(c.n3)
    #expect(n3.brightness == 40)
    #expect(n3.buttons["lcd_1"]?.action == "shell:open -a Notes")
    #expect(n3.knobs["big"]?.rotate.step == 5)

    let n4 = try #require(c.n4)
    #expect(n4.brightness == 60)
    #expect(n4.keys["key_1"]?.action == "shell:open -a Notes")
    #expect(n4.keys["key_1"]?.icon == "/tmp/notes.icns")
    #expect(n4.knobs["knob_1"]?.press.action == "system_mute_toggle")
    let internet = try #require(n4.strip["1"])
    #expect(internet.type == .internet)
    #expect(internet.host == "example.net")
    #expect(internet.arrowMs == 4)
    #expect(internet.timeoutS == 5)
    #expect(internet.action == "shell:open -a Terminal")
    #expect(n4.strip["2"]?.type == .load)
    #expect(n4.strip["2"]?.action == "shell:open -a 'Activity Monitor'")
    #expect(n4.strip["3"]?.type == .empty)
    #expect(n4.strip["4"]?.type == .volume)
    #expect(n4.swipe?.action == "key:cmd+tab")
    #expect(n4.lockPhoto == "/tmp/photo.jpg")
}

@Test func defaultsApply() throws {
    let c = try parse(#"{ "decks": { "n4": { "brightness": 50, "strip": { "1": { "type": "internet" } } } } }"#)
    let block = try #require(c.n4?.strip["1"])
    #expect(block.host == "one.one.one.one")
    #expect(block.arrowMs == 2)
    #expect(block.timeoutS == 3)
    #expect(block.action == nil)
    // An N4 section may leave out keys, knobs, strip, swipe and lock_photo.
    #expect(c.n4?.keys.isEmpty == true)
    #expect(c.n4?.knobs.isEmpty == true)
    #expect(c.n4?.swipe == nil)
    #expect(c.n4?.lockPhoto == nil)
    #expect(c.n3 == nil)
}

@Test func unknownBlockTypeThrows() {
    #expect(throws: (any Error).self) {
        try parse(#"{ "decks": { "n4": { "brightness": 50, "strip": { "1": { "type": "weather" } } } } }"#)
    }
}

@Test func decksWinsOverTopLevel() throws {
    let both = try parse("""
    { "brightness": 10, "buttons": { "lcd_1": { "action": "shell:old" } }, "knobs": {},
      "decks": { "n3": { "brightness": 70, "buttons": { "lcd_1": { "action": "shell:new" } }, "knobs": {} } } }
    """)
    #expect(both.n3?.brightness == 70)
    #expect(both.n3?.buttons["lcd_1"]?.action == "shell:new")

    // With `decks` present, a top-level N3 layout is ignored even when `decks` has no n3.
    let n4Only = try parse("""
    { "brightness": 10, "buttons": { "lcd_1": { "action": "shell:old" } }, "knobs": {},
      "decks": { "n4": { "brightness": 50 } } }
    """)
    #expect(n4Only.n3 == nil)
    #expect(n4Only.n4?.brightness == 50)
}

@Test func fileWithNeitherFormatThrows() {
    // Not a config at all: it must not load as an empty layout that blanks the deck.
    #expect(throws: (any Error).self) { try parse("{}") }
    // The v1.0.0 layout needs brightness, buttons and knobs, as it always did.
    #expect(throws: (any Error).self) { try parse(#"{ "brightness": 50, "buttons": {} }"#) }
}

@Test func exampleConfigParses() throws {
    let data = try Data(contentsOf: repoRoot.appendingPathComponent("config.example.json"))
    let c = try AppConfig.parse(data)
    #expect(c.n3?.buttons.count == 9)
    #expect(c.n3?.knobs.count == 3)
    #expect(c.n4?.strip.count == 4)
    #expect(c.displays?.count == 2)
}
