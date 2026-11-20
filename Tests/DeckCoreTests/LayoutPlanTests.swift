import CoreGraphics
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

/// The bounds of `image`'s red pixels, `y` counted from the top row.
private func redBox(_ image: CGImage) -> CGRect {
    let w = image.width, h = image.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    var box = CGRect.null
    for y in 0..<h {
        for x in 0..<w {
            let i = (y * w + x) * 4
            if buf[i] > 128 && buf[i + 1] < 100 && buf[i + 2] < 100 { box = box.union(CGRect(x: x, y: y, width: 1, height: 1)) }
        }
    }
    return box
}

// The N3 keeps a non-square icon's shape, on black, as the N4 and the app's drawing of both decks do (BL-007: it
// stretched it into the square, so a wide photo came out squashed on the deck and not in the app). A 2:1 picture
// fills the 77 pt between the margins one way and half that the other: in the app, upright, 77 wide × ~39 high; in
// the JPEG sent to the N3, turned 90° for the deck, ~39 wide and as long as a square icon is (the N3's own offsets
// put a few pixels of every icon past the JPEG's edge, as before).
@Test func n3KeepsTheIconsShape() throws {   // T-185
    func red(width: Int, height: Int) throws -> String {
        try writePNG(width: width, height: height) { ctx in
            ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
    let wide = try red(width: 200, height: 100)
    let app = redBox(try #require(DeckPreview.keyImage(path: wide, deck: .n3)))
    #expect(abs(app.width - 77) <= 2 && abs(app.height - 38.5) <= 2, "app \(app)")
    let square = redBox(try decodeImage(try #require(ImageLoader.loadAsJPEG(path: try red(width: 100, height: 100)))))
    let deck = redBox(try decodeImage(try #require(ImageLoader.loadAsJPEG(path: wide))))
    #expect(abs(deck.width - 38.5) <= 2, "deck \(deck): half the long side")
    #expect(abs(deck.height - square.height) <= 1, "deck \(deck), square \(square): as long as a square icon")
}
