import AppKit
import DeckCore
import SwiftUI
import Testing
@testable import DeckOutKit

/// Where snapshots go for a look (a temp folder, never the repo).
let snapshotFolder: URL = {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("deckout-snapshots")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}()

func solidImage(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, size: Int = 112) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    return ctx.makeImage()!
}

/// RGB at a point (points = pixels at scale 1), top-left origin.
func rgb(_ image: CGImage, _ x: CGFloat, _ y: CGFloat) -> (r: Int, g: Int, b: Int) {
    let rep = NSBitmapImageRep(cgImage: image)
    let c = rep.colorAt(x: Int(x), y: Int(y))?.usingColorSpace(.sRGB) ?? .black
    return (Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
}

@MainActor @Test func drawsImagesAndRing() throws {   // T-117
    let face = DeckFace.of(.n4)
    let view = DeckView(face: face, images: ["key_1": solidImage(1, 0, 0)], captions: ["knob_4": "Volume"],
                        selection: .constant("key_3"))
    let image = try #require(Snapshot.image(view, size: face.size, dark: false))
    try Snapshot.png(view, size: face.size, dark: false).write(to: snapshotFolder.appendingPathComponent("deck-n4-light.png"))
    try Snapshot.png(view, size: face.size, dark: true).write(to: snapshotFolder.appendingPathComponent("deck-n4-dark.png"))

    let key1 = try #require(face.control("key_1")).frame
    let inside = rgb(image, key1.midX, key1.midY)
    #expect(inside.r > 200 && inside.g < 60 && inside.b < 60, "key_1 shows its image: \(inside)")

    let key3 = try #require(face.control("key_3")).frame
    let ring = rgb(image, key3.midX, key3.minY - DeckView.ringGap - DeckView.ringWidth / 2)
    #expect(ring.r > 200 && ring.g < 90 && ring.b < 90, "key_3's ring is red: \(ring)")
    let empty = rgb(image, key3.midX, key3.midY - 12)
    #expect(empty.r < 90, "key_3 itself is an empty screen: \(empty)")

    // No ring around a control that isn't selected.
    let key2 = try #require(face.control("key_2")).frame
    let noRing = rgb(image, key2.midX, key2.minY - DeckView.ringGap - DeckView.ringWidth / 2)
    #expect(noRing.r < 120, "no ring on key_2: \(noRing)")

    // The N3 draws too.
    let n3 = DeckFace.of(.n3)
    let n3View = DeckView(face: n3, images: [:], captions: [:], selection: .constant("big"))
    try Snapshot.png(n3View, size: n3.size, dark: false).write(to: snapshotFolder.appendingPathComponent("deck-n3-light.png"))
}
