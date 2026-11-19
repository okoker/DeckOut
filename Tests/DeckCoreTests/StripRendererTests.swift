import CoreGraphics
import Foundation
import Testing
@testable import DeckCore

/// Image pixel of a point given in upright tile coordinates (CG, y up): the tile is turned 180°,
/// so upright (x, y) lands at image column 176 − x, row y counted from the top.
private func uprightPixel(_ img: CGImage, _ x: Int, _ yUp: Int) -> (r: Int, g: Int, b: Int) {
    pixel(img, StripRenderer.width - x, yUp)
}

@Test func volumeRendersAllStates() throws {
    for (percent, muted) in [(0, false), (45, false), (100, false), (45, true)] {
        let img = try decodeImage(StripRenderer.volume(percent: percent, muted: muted))
        #expect(img.width == 176 && img.height == 112)
    }
    #expect(StripRenderer.volume(percent: 45, muted: true) != StripRenderer.volume(percent: 45, muted: false))
    let unknown = try decodeImage(StripRenderer.volume(percent: nil, muted: false))
    #expect(unknown.width == 176)
}

@Test func volumeGaugeFillFollowsPercent() throws {
    // The point at 3 o'clock on the gauge is past half the sweep: lit at 100 %, unlit at 0 %.
    let full = uprightPixel(try decodeImage(StripRenderer.volume(percent: 100, muted: false)),
                            StripRenderer.gaugeCenter.x + StripRenderer.gaugeRadius, StripRenderer.gaugeCenter.y)
    let empty = uprightPixel(try decodeImage(StripRenderer.volume(percent: 0, muted: false)),
                             StripRenderer.gaugeCenter.x + StripRenderer.gaugeRadius, StripRenderer.gaugeCenter.y)
    #expect(full.b > 150)                                  // accent colour
    #expect(empty.b < 120 && abs(empty.r - empty.b) < 30)  // grey track
}
