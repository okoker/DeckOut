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
    #expect(n4.lockPhoto?.path == "/tmp/photo.jpg")
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
    let data = try Data(contentsOf: repoRoot.appendingPathComponent("Tests/DeckCoreTests/Fixtures/config-decks-no-presets.json"))
    let c = try AppConfig.parse(data)
    #expect(c.n3?.buttons.count == 9)
    #expect(c.n3?.knobs.count == 3)
    #expect(c.n4?.strip.count == 4)
    #expect(c.displays?.count == 2)
}

@Test func internetNumbersOutOfRangeAreRefused() throws {
    // A negative or huge timeout used to load fine and then crash the daemon at the first measurement
    // (UInt64(timeout * 1e9) traps), so launchd restarted it straight into the same crash.
    func block(_ fields: String) -> String {
        #"{ "decks": { "n4": { "brightness": 50, "strip": { "1": { "type": "internet", "# + fields + #" } } } } }"#
    }
    for bad in [#""timeout_s": -3"#, #""timeout_s": 0"#, #""timeout_s": 1e10"#, #""arrow_ms": -1"#] {
        #expect(throws: (any Error).self, "\(bad)") { try parse(block(bad)) }
    }
    let ok = try parse(block(#""timeout_s": 0.5, "arrow_ms": 0"#))
    #expect(ok.n4?.strip["1"]?.timeoutS == 0.5)
    #expect(ok.n4?.strip["1"]?.arrowMs == 0)
}

// MARK: - Presets and encoding

private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: repoRoot.appendingPathComponent(name))
}

private let presetsConfig = """
{
  "displays": [ { "name": "Left", "serial": "S1" }, { "name": "Right", "serial": "S2" } ],
  "decks": {
    "n3": {
      "brightness": 40,
      "knobs": { "big": { "rotate": { "action": "system_volume", "step": 5 },
                          "press":  { "action": "system_mute_toggle", "step": -2 } } },
      "presets": [
        { "name": "Work",  "buttons": { "lcd_1": { "action": "system_volume", "icon": "/i/a.png", "step": 5 } } },
        { "name": "Music", "buttons": { "lcd_1": { "action": "shell:open -a Music" } } }
      ],
      "active_preset": "Music"
    },
    "n4": {
      "brightness": 60,
      "knobs": { "knob_1": { "rotate": { "action": "display_brightness", "step": 5 },
                             "press":  { "action": "display_brightness_cycle" } } },
      "swipe": { "action": "system_volume", "step": -5 },
      "lock_photo": "/tmp/photo.jpg",
      "presets": [
        { "name": "Work",
          "keys": { "key_1": { "action": "shell:open -a Notes", "icon": "/i/notes.icns" },
                    "key_2": { "action": "system_volume", "step": -5 } },
          "strip": { "1": { "type": "internet", "host": "example.net", "arrow_ms": 4, "timeout_s": 5,
                            "action": "shell:open -a Terminal", "step": 3 },
                     "2": { "type": "picture", "icon": "/i/pic.png" },
                     "3": { "type": "empty" } } },
        { "name": "Music",
          "keys": { "key_1": { "action": "shell:open -a Music" } },
          "strip": { "1": { "type": "volume", "action": "system_mute_toggle" } } }
      ],
      "active_preset": "Music"
    }
  }
}
"""

@Test func roundTripKeepsEveryField() throws {                      // T-063
    let original = try parse(presetsConfig)
    let again = try AppConfig.parse(try original.encoded())
    #expect(again == original)
    #expect(again.n4?.presets.count == 2)
    #expect(again.n3?.presets.count == 2)
}

@Test func oldFilesReadAsOneDefaultPreset() throws {                // T-064
    let v1 = try AppConfig.parse(try fixture("Tests/DeckCoreTests/Fixtures/config-v1.0.0.json"))
    let decks = try AppConfig.parse(try fixture("Tests/DeckCoreTests/Fixtures/config-decks-no-presets.json"))
    for config in [v1, decks] {
        let n3 = try #require(config.n3)
        #expect(n3.presets.map(\.name) == ["Default"])
        #expect(n3.activePreset == "Default")
        #expect(n3.buttons.count == 9)
        #expect(n3.buttons["lcd_4"]?.action == "key:cmd+space")
    }
    let n4 = try #require(decks.n4)
    #expect(n4.presets.map(\.name) == ["Default"])
    #expect(n4.activePreset == "Default")
    #expect(n4.keys.count == 3)
    #expect(n4.strip.count == 4)
}

@Test func activePresetPicksKeysAndStrip() throws {                 // T-065
    let c = try parse(presetsConfig)
    let n4 = try #require(c.n4)
    #expect(n4.keys["key_1"]?.action == "shell:open -a Music")
    #expect(n4.keys["key_2"] == nil)
    #expect(n4.strip["1"]?.type == .volume)
    #expect(c.n3?.buttons["lcd_1"]?.action == "shell:open -a Music")
    #expect(ActionResolver.resolve(.keyDown("key_1"), deck: .n4, config: c)
            == ResolvedAction(action: "shell:open -a Music", step: nil))
    #expect(ActionResolver.resolve(.stripTap("1"), deck: .n4, config: c)
            == ResolvedAction(action: "system_mute_toggle", step: nil))
}

@Test func unknownActivePresetFallsBackToFirst() throws {           // T-066
    let c = try parse(presetsConfig.replacingOccurrences(of: #""active_preset": "Music""#, with: #""active_preset": "Gone""#))
    #expect(c.n4?.activePreset == "Gone")
    #expect(c.n4?.keys["key_1"]?.action == "shell:open -a Notes")     // Work, the first
    #expect(c.n4?.strip["1"]?.type == .internet)
    #expect(c.n3?.buttons["lcd_1"]?.action == "system_volume")
}

@Test func duplicateOrEmptyPresetNamesAreRefused() {                // T-067
    for presets in [#"[{"name":"A"},{"name":"A"}]"#, #"[{"name":""}]"#, "[]"] {
        #expect(throws: (any Error).self, "n4 \(presets)") {
            try parse(#"{ "decks": { "n4": { "brightness": 50, "presets": "# + presets + " } } }")
        }
        #expect(throws: (any Error).self, "n3 \(presets)") {
            try parse(#"{ "decks": { "n3": { "brightness": 50, "knobs": {}, "presets": "# + presets + " } } }")
        }
    }
}

@Test func encodedFileUsesTheDecksFormat() throws {                 // T-068
    let v1 = try AppConfig.parse(try fixture("Tests/DeckCoreTests/Fixtures/config-v1.0.0.json"))
    let object = try #require(try JSONSerialization.jsonObject(with: try v1.encoded()) as? [String: Any])
    #expect(object["buttons"] == nil)
    #expect(object["brightness"] == nil)
    #expect(object["knobs"] == nil)
    let n3 = try #require((object["decks"] as? [String: Any])?["n3"] as? [String: Any])
    let presets = try #require(n3["presets"] as? [[String: Any]])
    #expect(presets.first?["name"] as? String == "Default")
    #expect(n3["active_preset"] as? String == "Default")
    #expect(n3["buttons"] == nil)

    // The v1.0.0 file has no N4: the strip check uses the decks file without presets.
    let example = try AppConfig.parse(try fixture("Tests/DeckCoreTests/Fixtures/config-decks-no-presets.json"))
    let exampleObject = try #require(try JSONSerialization.jsonObject(with: try example.encoded()) as? [String: Any])
    let n4 = try #require((exampleObject["decks"] as? [String: Any])?["n4"] as? [String: Any])
    #expect(n4["keys"] == nil)
    #expect(n4["strip"] == nil)
    let strip = try #require((n4["presets"] as? [[String: Any]])?.first?["strip"] as? [String: [String: Any]])
    #expect(strip["3"]?["type"] as? String == "empty")
    for key in ["host", "arrow_ms", "timeout_s"] {
        #expect(strip["3"]?[key] == nil, "\(key)")
        #expect(strip["1"]?[key] != nil, "\(key)")
    }
}

// MARK: - Lock photo framing

@Test func lockPhotoReadsStringOrObject() throws {                  // T-074
    func n4(_ lockPhoto: String) throws -> N4Section? {
        try parse(#"{ "decks": { "n4": { "brightness": 50, "lock_photo": "# + lockPhoto + " } } }").n4
    }
    #expect(try n4(#""/p.jpg""#)?.lockPhoto == LockPhotoConfig(path: "/p.jpg", zoom: 1, offsetX: 0, offsetY: 0))
    #expect(try n4(#"{ "path": "/q.jpg", "zoom": 2.5, "offset_x": -0.25, "offset_y": 0.2 }"#)?.lockPhoto
            == LockPhotoConfig(path: "/q.jpg", zoom: 2.5, offsetX: -0.25, offsetY: 0.2))
    #expect(try n4(#"{ "path": "/q.jpg" }"#)?.lockPhoto == LockPhotoConfig(path: "/q.jpg", zoom: 1, offsetX: 0, offsetY: 0))
    for zoom in ["0.5", "11"] {
        #expect(throws: (any Error).self, "zoom \(zoom)") {
            try n4(#"{ "path": "/q.jpg", "zoom": "# + zoom + " }")
        }
    }
}

@Test func tileRoundTripsAndIsOptional() throws {                   // T-139
    // How a generated icon was made rides along with the key; the agent only ever draws `icon`.
    let tile = IconTile(kind: .symbol, text: nil, symbol: "acorn", style: "fill", background: "#0F8A7E", foreground: nil)
    let config = AppConfig(n4: N4Section(brightness: 75, swipe: nil, lockPhoto: nil,
                                         presets: [N4Preset(name: "Default",
                                                            keys: ["key_1": ButtonConfig(action: "none", icon: "/i.png", tile: tile)],
                                                            strip: [:])],
                                         activePreset: "Default"))
    #expect(try AppConfig.parse(config.encoded()) == config)
    let text = IconTile(kind: .text, text: "Stand\nup", symbol: nil, style: nil, background: "#C35A00", foreground: "#FFFFFF")
    #expect(try JSONDecoder().decode(IconTile.self, from: JSONEncoder().encode(text)) == text)
    // Files without it (every file today) load as before.
    let old = #"{"decks":{"n4":{"brightness":75,"keys":{"key_1":{"action":"none","icon":"/i.png"}}}}}"#
    #expect(try AppConfig.parse(Data(old.utf8)).n4?.keys["key_1"]?.tile == nil)
}

@Test func stripBlockKeepsItsTile() throws {                        // T-155
    // A strip block's generated icon remembers how it was made, as a key's does; the agent only draws `icon`.
    let tile = IconTile(kind: .text, text: "Weather", symbol: nil, style: nil, background: "#0A84FF", foreground: nil)
    let block = StripBlockConfig(type: .picture, action: "shell:echo hi", icon: "/icons/tile-1.png", tile: tile)
    let config = AppConfig(n4: N4Section(brightness: 75, swipe: nil, lockPhoto: nil,
                                         presets: [N4Preset(name: "Default", keys: [:], strip: ["3": block])],
                                         activePreset: "Default"))
    #expect(try AppConfig.parse(config.encoded()) == config)
    // A tile that doesn't read (a hand-edit typo, a newer app) reads as none; the block and the file still load.
    let odd = #"{"decks":{"n4":{"brightness":75,"strip":{"3":{"type":"picture","icon":"/i.png","action":"shell:echo hi","tile":{"kind":"sparkle"}}}}}}"#
    #expect(try AppConfig.parse(Data(odd.utf8)).n4?.strip["3"] == StripBlockConfig(type: .picture, action: "shell:echo hi", icon: "/i.png"))
    // A block without one (every file today) writes no `tile`.
    let plain = String(decoding: try JSONEncoder().encode(StripBlockConfig(type: .picture, icon: "/i.png")), as: UTF8.self)
    #expect(!plain.contains("tile"))
}

@Test func emptyHostReadsAsTheDefault() throws {                    // T-166
    // A Host field emptied before BL-013's fix saved `"host": ""`, and the agent pinged nothing: such a file reads as
    // the default host, in the agent and in the app.
    for host in [#""""#, #""  ""#, #"" \n""#] {
        let c = try parse(#"{ "decks": { "n4": { "brightness": 50, "strip": { "1": { "type": "internet", "host": "# + host + " } } } } }")
        #expect(c.n4?.strip["1"]?.host == StripBlockConfig.defaultHost, "\(host)")
    }
}

// MARK: - Knobs per preset, knob lists (docs/design/knob_lists.md)

private let volumeKnobJSON = #"{ "rotate": { "action": "system_volume", "step": 5 }, "press": { "action": "system_mute_toggle" } }"#
private let brightnessKnobJSON =
    #"{ "rotate": { "action": "display_brightness", "step": 5 }, "press": { "action": "display_brightness_cycle" } }"#
private let volumeKnob = KnobConfig(rotate: KnobAction(action: "system_volume", step: 5),
                                    press: KnobAction(action: "system_mute_toggle"))
private let brightnessKnob = KnobConfig(rotate: KnobAction(action: "display_brightness", step: 5),
                                        press: KnobAction(action: "display_brightness_cycle"))

@Test func oldKnobsGoIntoEveryPreset() throws {                     // T-196
    // A 2.1.0 file: knobs on the deck. Every preset gets them, so the decks behave as before.
    let c = try parse("""
    { "decks": {
        "n3": { "brightness": 50, "knobs": { "big": \(volumeKnobJSON), "small_1": \(brightnessKnobJSON) },
                "presets": [ { "name": "A", "buttons": {} }, { "name": "B", "buttons": {} } ], "active_preset": "B" },
        "n4": { "brightness": 50, "knobs": { "knob_1": \(brightnessKnobJSON), "knob_4": \(volumeKnobJSON) },
                "presets": [ { "name": "Work" }, { "name": "Music" } ], "active_preset": "Work" } } }
    """)
    let n3Knobs = ["big": volumeKnob, "small_1": brightnessKnob]
    let n4Knobs = ["knob_1": brightnessKnob, "knob_4": volumeKnob]
    #expect(c.n3!.presets.map(\.knobs) == [n3Knobs, n3Knobs])
    #expect(c.n4!.presets.map(\.knobs) == [n4Knobs, n4Knobs])
    #expect(c.n3!.knobs == n3Knobs)                                   // the live preset's
    // A section from before presets: its one preset, Default, gets them.
    let old = try parse(#"{ "decks": { "n4": { "brightness": 50, "knobs": { "knob_4": "# + volumeKnobJSON + " } } } }")
    #expect(old.n4!.presets[0].knobs == ["knob_4": volumeKnob])
    // An N3 with presets may leave out the deck's knobs now.
    let noKnobs = try parse(#"{ "decks": { "n3": { "brightness": 50, "presets": [ { "name": "A" } ] } } }"#)
    #expect(noKnobs.n3!.knobs.isEmpty)
    // Written in every preset, never on the deck.
    let object = try #require(try JSONSerialization.jsonObject(with: try c.encoded()) as? [String: Any])
    let decks = try #require(object["decks"] as? [String: Any])
    for deck in ["n3", "n4"] {
        let section = try #require(decks[deck] as? [String: Any])
        #expect(section["knobs"] == nil, "\(deck)")
        let presets = try #require(section["presets"] as? [[String: Any]])
        #expect(presets.count == 2 && presets.allSatisfy { ($0["knobs"] as? [String: Any])?.count == 2 }, "\(deck)")
    }
}

@Test func presetKnobsWinOverDeckKnobs() throws {                   // T-197
    // A preset with its own knobs, even none, keeps them; one without the key gets the deck's.
    let c = try parse("""
    { "decks": { "n4": { "brightness": 50, "knobs": { "knob_1": \(volumeKnobJSON) },
        "presets": [ { "name": "A", "knobs": {} }, { "name": "B" } ] } } }
    """)
    #expect(c.n4!.presets[0].knobs.isEmpty)
    #expect(c.n4!.presets[1].knobs == ["knob_1": volumeKnob])
}

@Test func listKnobRoundTrips() throws {                            // T-198
    let c = try parse("""
    { "decks": { "n4": { "brightness": 50, "presets": [ { "name": "A", "knobs": { "knob_1": { "list": [
        { "action": "url:https://github.com", "icon": "/tmp/g.png" },
        { "action": "app:/Applications/Safari.app", "tile": { "kind": "text", "text": "Safari", "background": "#0A84FF" } }
    ] } } } ] } } }
    """)
    let knob = try #require(c.n4?.knobs["knob_1"])
    #expect(knob.list?.map(\.action) == ["url:https://github.com", "app:/Applications/Safari.app"])
    #expect(knob.list?[0].icon == "/tmp/g.png")
    #expect(knob.list?[1].tile?.text == "Safari")
    #expect(knob.rotate.action == "none" && knob.press.action == "none")
    // Written as the list alone, and read back the same.
    let encoded = try c.encoded()
    let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let n4 = try #require((object["decks"] as? [String: Any])?["n4"] as? [String: Any])
    let preset = try #require((n4["presets"] as? [[String: Any]])?.first)
    let written = try #require((preset["knobs"] as? [String: Any])?["knob_1"] as? [String: Any])
    #expect(Array(written.keys) == ["list"])
    #expect(try AppConfig.parse(encoded) == c)
}

@Test func badKnobsAreRefused() throws {                            // T-199
    func n4(_ knob: String) -> String {
        #"{ "decks": { "n4": { "brightness": 50, "presets": [ { "name": "A", "knobs": { "knob_1": "# + knob + " } } ] } } }"
    }
    // A list and a turn or press, or neither.
    #expect(throws: (any Error).self) {
        try parse(n4(#"{ "list": [], "rotate": { "action": "system_volume" }, "press": { "action": "none" } }"#))
    }
    #expect(throws: (any Error).self) { try parse(n4(#"{ "list": [], "press": { "action": "none" } }"#)) }
    #expect(throws: (any Error).self) { try parse(n4("{}")) }
    // A list on the N3, which has no screen above its knobs: in a preset, or on the deck of an old file.
    #expect(throws: (any Error).self) {
        try parse(#"{ "decks": { "n3": { "brightness": 50, "presets": [ { "name": "A", "knobs": { "big": { "list": [] } } } ] } } }"#)
    }
    #expect(throws: (any Error).self) {
        try parse(#"{ "decks": { "n3": { "brightness": 50, "knobs": { "big": { "list": [] } }, "buttons": {} } } }"#)
    }
    // An empty list on the N4 is fine: the app saves after every change, so a list starts empty.
    #expect(try parse(n4(#"{ "list": [] }"#)).n4?.knobs["knob_1"]?.list == [])
}

@Test func builtInsOnlyKeepsVolumeAndBrightness() {                 // T-200
    // What New Preset copies from a knob: only the halves that are built-in actions.
    let volumeAndApp = KnobConfig(rotate: KnobAction(action: "system_volume", step: 5),
                                  press: KnobAction(action: "app:/Applications/Safari.app"))
    #expect(volumeAndApp.builtInsOnly() == KnobConfig(rotate: KnobAction(action: "system_volume", step: 5),
                                                      press: KnobAction(action: "none")))
    #expect(brightnessKnob.builtInsOnly() == brightnessKnob)
    #expect(volumeKnob.builtInsOnly() == volumeKnob)
    #expect(KnobConfig(list: [ButtonConfig(action: "url:https://github.com")]).builtInsOnly() == nil)
    #expect(KnobConfig(rotate: KnobAction(action: "none"), press: KnobAction(action: "shell:ls")).builtInsOnly() == nil)
}
