import CoreGraphics
import Foundation
import Testing
@testable import DeckCore

/// A cache whose renders are counted (the real rendering underneath).
private final class RenderCount { var value = 0 }

private func countingCache() -> (SlotImageCache, RenderCount) {
    let count = RenderCount()
    let cache = SlotImageCache { content, bytes, slot, model in
        count.value += 1
        return LayoutPlan.render(content, bytes: bytes, slot: slot, model: model)
    }
    return (cache, count)
}

/// A PNG of one colour, in a fresh temporary file.
private func solidPNG(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) throws -> String {
    try writePNG(width: 64, height: 64) { ctx in
        ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    }
}

/// Writes `source`'s bytes over `path`, in place, as a script rewriting its icon would.
private func copyBytes(of source: String, over path: String) throws {
    try Data(contentsOf: URL(fileURLWithPath: source)).write(to: URL(fileURLWithPath: path))
}

/// The colour in the middle of a slot image.
private func middle(_ jpeg: Data?) throws -> (r: Int, g: Int, b: Int) {
    let image = try decodeImage(try #require(jpeg))
    return pixel(image, image.width / 2, image.height / 2)
}

@Test func unchangedFileRendersOnce() throws {   // T-169
    let (cache, renders) = countingCache()
    let plan: [UInt8: SlotContent] = [11: .icon(try solidPNG(1, 0, 0))]
    let first = cache.images(plan: plan, model: .n4)
    let second = cache.images(plan: plan, model: .n4)
    #expect(renders.value == 1)
    #expect(first[11] != nil && first[11] == second[11])
}

@Test func anIconRewrittenInPlaceShowsItsNewPicture() throws {   // T-169
    // A script rewrites its key's icon at the same path, then posts a reload.
    let (cache, renders) = countingCache()
    let icon = try solidPNG(1, 0, 0), other = try solidPNG(0, 1, 0)
    let plan: [UInt8: SlotContent] = [11: .icon(icon), 12: .icon(other), 2: .blank]
    var shown = ShownSlots()
    let before = cache.images(plan: plan, model: .n4)
    for (slot, jpeg) in before { shown.record(slot, jpeg) }
    #expect(try middle(before[11]).r > 200)
    #expect(renders.value == 2)

    let blue = try solidPNG(0, 0, 1)
    try copyBytes(of: blue, over: icon)
    let rewritten = cache.images(plan: plan, model: .n4)
    #expect(renders.value == 3)                          // only the rewritten file renders again
    let colour = try middle(rewritten[11])
    #expect(colour.b > 200 && colour.r < 60)
    #expect(shown.changed(rewritten) == [11])
    for (slot, jpeg) in rewritten { shown.record(slot, jpeg) }

    // The same bytes written again, with a later modification date: nothing renders, nothing changes.
    try copyBytes(of: blue, over: icon)
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: icon)
    let again = cache.images(plan: plan, model: .n4)
    #expect(renders.value == 3)
    #expect(shown.changed(again).isEmpty)
}

@Test func aMissingFileIsBlackUntilItAppears() throws {   // T-169
    let (cache, renders) = countingCache()
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("deckcore-test-\(UUID().uuidString).png").path
    let plan: [UInt8: SlotContent] = [1: .icon(path)]
    let missing = cache.images(plan: plan, model: .n3)
    #expect(renders.value == 0)
    let black = try decodeImage(try #require(missing[1]))
    #expect(black.width == 85 && black.height == 85)
    let dark = pixel(black, 42, 42)
    #expect(dark.r < 10 && dark.g < 10 && dark.b < 10)

    try copyBytes(of: try solidPNG(1, 0, 0), over: path)
    let appeared = cache.images(plan: plan, model: .n3)
    #expect(renders.value == 1)
    #expect(try middle(appeared[1]).r > 200)
}

@Test func liveBlocksAreNeverCached() throws {   // T-169
    let (cache, renders) = countingCache()
    let plan: [UInt8: SlotContent] = [1: .strip(.internet), 2: .blank, 3: .strip(.load),
                                      4: .picture(try solidPNG(1, 0, 0))]
    let first = cache.images(plan: plan, model: .n4)
    let second = cache.images(plan: plan, model: .n4)
    #expect(first[1] == nil && first[3] == nil)          // the Daemon draws them from their readings
    #expect(renders.value == 1)                          // the picture only
    #expect(first[2] != nil && first[2] == second[2])    // a blank slot's image is the same every pass

    // A live image is made from the reading each pass: the same reading gives the same bytes (nothing to send),
    // a new one different bytes (sent).
    #expect(StripRenderer.load(cpu: 20, mem: 40, memLevel: .normal) == StripRenderer.load(cpu: 20, mem: 40, memLevel: .normal))
    #expect(StripRenderer.load(cpu: 20, mem: 40, memLevel: .normal) != StripRenderer.load(cpu: 21, mem: 40, memLevel: .normal))
    #expect(StripRenderer.internet(ms: 12, trend: .none, failed: false) == StripRenderer.internet(ms: 12, trend: .none, failed: false))
    #expect(StripRenderer.internet(ms: 12, trend: .none, failed: false) != StripRenderer.internet(ms: 13, trend: .none, failed: false))
}

@Test func aFileNoLongerShownIsDropped() throws {   // T-169
    let (cache, renders) = countingCache()
    let a = try solidPNG(1, 0, 0), b = try solidPNG(0, 0, 1)
    _ = cache.images(plan: [11: .icon(a)], model: .n4)
    _ = cache.images(plan: [11: .icon(b)], model: .n4)
    _ = cache.images(plan: [11: .icon(a)], model: .n4)
    #expect(renders.value == 3)
}

@Test func changedNamesTheSlotsThatDiffer() {   // T-169
    var shown = ShownSlots()
    let a = Data([1]), b = Data([2])
    let wanted: [UInt8: Data] = [3: b, 1: a, 2: a]
    #expect(shown.changed(wanted) == [1, 2, 3])                   // never recorded
    for (slot, jpeg) in wanted { shown.record(slot, jpeg) }
    #expect(shown.changed(wanted).isEmpty)
    #expect(shown.changed([1: a, 2: b, 3: b]) == [2])
    #expect(shown.changed(wanted, everySlot: true) == [1, 2, 3])
    shown.forget(2)                                               // a failed send
    #expect(shown.changed(wanted) == [2])
    shown.forgetAll()                                             // a clear
    #expect(shown.changed(wanted) == [1, 2, 3])
}

@Test func bytesRenderAsThePathDid() throws {   // T-169
    // The cache renders from the bytes it read; the image is the one the path loaders made before.
    let path = try redTopBlueBottomPNG(width: 120, height: 80)
    let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
    for (content, slot, model) in [(SlotContent.icon(path), UInt8(1), DeckModel.n3), (.icon(path), 11, .n4),
                                   (.picture(path), 2, .n4)] {
        #expect(LayoutPlan.render(content, bytes: bytes, slot: slot, model: model)
                == LayoutPlan.render(content, slot: slot, model: model))
    }
    // Bytes that aren't an image fall back to black, as a file that isn't one does.
    let junk = try decodeImage(LayoutPlan.render(.icon(path), bytes: Data("not a picture".utf8), slot: 11, model: .n4))
    #expect(junk.width == 112 && pixel(junk, 56, 56).r < 10)
}
