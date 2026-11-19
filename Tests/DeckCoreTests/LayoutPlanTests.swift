import Foundation
import Testing
@testable import DeckCore

private func config(_ json: String) throws -> AppConfig {
    try AppConfig.parse(Data(json.utf8))
}

private let sample = """
{ "decks": {
  "n3": { "brightness": 50, "knobs": {},
          "buttons": { "lcd_1": { "action": "none", "icon": "/icons/a.icns" }, "lcd_2": { "action": "shell:x" } } },
  "n4": { "brightness": 50,
          "keys": { "key_1": { "action": "none", "icon": "/icons/b.icns" }, "key_2": { "action": "shell:y" } },
          "strip": { "1": { "type": "internet" }, "2": { "type": "picture", "icon": "/icons/c.png" },
                     "3": { "type": "empty" }, "4": { "type": "picture" } } } } }
"""

@Test func n4PlanCoversAll14Slots() throws {
    let plan = LayoutPlan.slots(model: .n4, config: try config(sample))
    #expect(plan.keys.sorted() == [1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15])
}

@Test func n3PlanCoversSixSlots() throws {
    let plan = LayoutPlan.slots(model: .n3, config: try config(sample))
    #expect(plan.keys.sorted() == [1, 2, 3, 4, 5, 6])
}

@Test func keysShowTheirIconOrBlank() throws {
    let c = try config(sample)
    let n4 = LayoutPlan.slots(model: .n4, config: c)
    #expect(n4[11] == .icon("/icons/b.icns"))   // key_1, top row
    #expect(n4[12] == .blank)                   // key_2: an action but no icon
    #expect(n4[10] == .blank)                   // key_10: not configured
    let n3 = LayoutPlan.slots(model: .n3, config: c)
    #expect(n3[1] == .icon("/icons/a.icns"))
    #expect(n3[2] == .blank)
    #expect(n3[6] == .blank)
}

@Test func stripBlocksMapToTheirContent() throws {
    let plan = LayoutPlan.slots(model: .n4, config: try config(sample))
    #expect(plan[1] == .strip(.internet))
    #expect(plan[2] == .picture("/icons/c.png"))
    #expect(plan[3] == .blank)                  // empty
    #expect(plan[4] == .blank)                  // picture without an icon
}

@Test func deckWithoutSectionIsAllBlank() throws {
    let c = try config(#"{ "decks": { "n3": { "brightness": 50, "buttons": {}, "knobs": {} } } }"#)
    let plan = LayoutPlan.slots(model: .n4, config: c)
    #expect(plan.count == 14)
    #expect(plan.values.allSatisfy { $0 == .blank })
}

@Test func rendererFallsBackToBlank() throws {
    let key = try decodeImage(LayoutPlan.render(.icon("/nonexistent.png"), slot: 11, model: .n4))
    #expect(key.width == 112 && key.height == 112)
    let p = pixel(key, 56, 56)
    #expect(p.r < 10 && p.g < 10 && p.b < 10)

    let block = try decodeImage(LayoutPlan.render(.picture("/nonexistent.png"), slot: 2, model: .n4))
    #expect(block.width == 176 && block.height == 112)

    let n3 = try decodeImage(LayoutPlan.render(.icon("/nonexistent.png"), slot: 1, model: .n3))
    #expect(n3.width == 85 && n3.height == 85)
}

@Test func n3IconsUseTheN3Pipeline() throws {
    // The N3 keeps its 85×85 v1.0.0 rendering; an N4 key renders the same file at 112×112.
    let path = try redTopBlueBottomPNG()
    #expect(try decodeImage(LayoutPlan.render(.icon(path), slot: 1, model: .n3)).width == 85)
    #expect(try decodeImage(LayoutPlan.render(.icon(path), slot: 11, model: .n4)).width == 112)
}
