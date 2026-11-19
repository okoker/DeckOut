import CoreGraphics
import Foundation
import Testing
@testable import DeckCore

// The decks as the app draws them: where each control sits, and its images upright.

@Test func n4MatchesMeasuredRects() throws {   // T-114
    let face = DeckFace.of(.n4)
    let padding = CGPoint(x: DeckFace.n4Padding.left, y: DeckFace.n4Padding.top)
    for (key, slot) in DeckModel.n4.keySlots {
        let measured = try #require(LockPhoto.n4Rects[slot])
        let control = try #require(face.controls.first { $0.id == key })
        #expect(control.kind == .key)
        #expect(control.frame == CGRect(x: padding.x + measured.minX / 2, y: padding.y + measured.minY / 2,
                                        width: measured.width / 2, height: measured.height / 2), "\(key)")
    }
    for (block, slot) in DeckModel.n4.stripSlots {
        let measured = try #require(LockPhoto.n4Rects[slot])
        let control = try #require(face.controls.first { $0.id == block })
        #expect(control.kind == .stripBlock)
        #expect(control.frame == CGRect(x: padding.x + measured.minX / 2, y: padding.y + measured.minY / 2,
                                        width: measured.width / 2, height: measured.height / 2), "block \(block)")
    }
    // Every control sits inside the deck.
    for control in face.controls {
        #expect(CGRect(origin: .zero, size: face.size).contains(control.frame), "\(control.id)")
    }
    #expect(face.controls.first { $0.id == "key_3" }?.label == "Key 3 · top row")
    #expect(face.controls.first { $0.id == "key_8" }?.label == "Key 8 · bottom row")
    #expect(face.controls.first { $0.id == "2" }?.label == "Strip block 2")
    #expect(face.controls.first { $0.id == "knob_4" }?.label == "Knob 4")
}

@Test func everyConfigKeyOnce() {   // T-115
    let n3 = DeckFace.of(.n3).controls
    #expect(Set(n3.map(\.id)) == ["lcd_1", "lcd_2", "lcd_3", "lcd_4", "lcd_5", "lcd_6", "btn_1", "btn_2", "btn_3",
                                  "big", "small_1", "small_2"])
    #expect(n3.count == 12)
    #expect(n3.filter { $0.kind == .key }.map(\.id).sorted() == DeckModel.n3.keySlots.keys.sorted())
    #expect(n3.filter { $0.kind == .button }.count == 3)
    #expect(n3.filter { $0.kind == .knob }.count == 3)

    let n4 = DeckFace.of(.n4).controls
    #expect(n4.count == 18)
    #expect(n4.filter { $0.kind == .key }.map(\.id).sorted() == DeckModel.n4.keySlots.keys.sorted())
    #expect(n4.filter { $0.kind == .stripBlock }.map(\.id).sorted() == ["1", "2", "3", "4"])
    #expect(n4.filter { $0.kind == .knob }.map(\.id).sorted() == ["knob_1", "knob_2", "knob_3", "knob_4"])

    // No two controls overlap.
    for face in [DeckFace.of(.n3), DeckFace.of(.n4)] {
        for (i, a) in face.controls.enumerated() {
            for b in face.controls[(i + 1)...] {
                #expect(!a.frame.intersects(b.frame), "\(a.id) overlaps \(b.id)")
            }
        }
    }
}

@Test func previewIsUpright() throws {   // T-116
    // An icon red at the top, blue at the bottom: the preview shows it that way up (the deck's copy is turned).
    let icon = try redTopBlueBottomPNG()
    for deck in [DeckKind.n3, .n4] {
        let preview = try #require(DeckPreview.keyImage(path: icon, deck: deck))
        #expect(preview.width == (deck == .n4 ? 112 : 85))
        let top = pixel(preview, preview.width / 2, 12), bottom = pixel(preview, preview.width / 2, preview.height - 12)
        #expect(top.r > 200 && top.b < 60, "\(deck) top \(top)")
        #expect(bottom.b > 200 && bottom.r < 60, "\(deck) bottom \(bottom)")
    }
    let picture = try #require(DeckPreview.stripPicture(path: icon))
    #expect(picture.width == 176 && picture.height == 112)
    #expect(pixel(picture, 88, 10).r > 200)

    // A live block as the deck gets it (turned 180°) comes back upright: the volume gauge's ring is open at the
    // bottom, so the bottom-centre is dark and the top-centre is on the ring.
    let jpeg = StripRenderer.volume(percent: 100, muted: false)
    let upright = try #require(DeckPreview.upright(jpeg: jpeg))
    let ringTop = pixel(upright, 88, 56 - StripRenderer.gaugeRadius)
    let gapBottom = pixel(upright, 88, 56 + StripRenderer.gaugeRadius)
    func isRing(_ p: (r: Int, g: Int, b: Int)) -> Bool { p.b > 180 && p.r < 120 }   // the accent blue
    #expect(isRing(ringTop), "ring at the top: \(ringTop)")
    #expect(!isRing(gapBottom), "gap at the bottom: \(gapBottom)")

    #expect(DeckPreview.keyImage(path: "/nonexistent.png", deck: .n4) == nil)
}
