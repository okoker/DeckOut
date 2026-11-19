import Foundation
import Testing
@testable import DeckCore

// MARK: - Packets

@Test func batHeaderCarriesWireSlotAndLength() {
    let p = CRTCommand.makeBAT(imageLength: 0x1234, slot: 11)
    #expect(p.count == 1025)
    #expect(Array(p.prefix(14)) == [0x00, 0x43, 0x52, 0x54, 0x00, 0x00, 0x42, 0x41, 0x54, 0x00, 0x00, 0x12, 0x34, 11])
    #expect(p.dropFirst(14).allSatisfy { $0 == 0 })
    // N3 lcd_1 is wire slot 1, as before the slot-based header.
    #expect(CRTCommand.makeBAT(imageLength: 1, slot: DeckModel.n3.keySlots["lcd_1"]!)[13] == 1)
}

// MARK: - N4 key icons

@Test func n4IconIs112SquareAndTurned180() throws {
    let jpeg = try #require(IconImage.renderN4(path: try redTopBlueBottomPNG()))
    let img = try decodeImage(jpeg)
    #expect(img.width == 112 && img.height == 112)
    let top = pixel(img, 56, 20), bottom = pixel(img, 56, 92)
    #expect(top.b > 200 && top.r < 60)        // the picture's bottom (blue) is now on top
    #expect(bottom.r > 200 && bottom.b < 60)
    let corner = pixel(img, 1, 1)             // 4 px margin stays black
    #expect(corner.r < 30 && corner.g < 30 && corner.b < 30)
}

@Test func n4IconKeepsProportions() throws {
    // A wide white picture fits the width and leaves black bands above and below.
    let path = try writePNG(width: 200, height: 100) { ctx in
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
    }
    let img = try decodeImage(try #require(IconImage.renderN4(path: path)))
    let band = pixel(img, 56, 15), middle = pixel(img, 56, 56)
    #expect(band.r < 30 && band.g < 30 && band.b < 30)
    #expect(middle.r > 220 && middle.g > 220 && middle.b > 220)
}

@Test func n4IconMissingFileIsNil() {
    #expect(IconImage.renderN4(path: "/nonexistent/icon.png") == nil)
}

// MARK: - Strip tiles

@Test func stripBlankIsBlackAtSize() throws {
    let img = try decodeImage(StripRenderer.blank(w: 176, h: 112))
    #expect(img.width == 176 && img.height == 112)
    let p = pixel(img, 88, 56)
    #expect(p.r < 10 && p.g < 10 && p.b < 10)
}

@Test func stripPictureIs176x112AndTurned180() throws {
    let img = try decodeImage(try #require(StripRenderer.picture(path: try redTopBlueBottomPNG())))
    #expect(img.width == 176 && img.height == 112)
    let top = pixel(img, 88, 25), bottom = pixel(img, 88, 87)
    #expect(top.b > 200 && top.r < 60)
    #expect(bottom.r > 200 && bottom.b < 60)
}

@Test func stripPictureMissingFileIsNil() {
    #expect(StripRenderer.picture(path: "/nonexistent/pic.png") == nil)
}
