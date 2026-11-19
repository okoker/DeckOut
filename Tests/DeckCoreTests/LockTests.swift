import CoreGraphics
import Foundation
import Testing
@testable import DeckCore

// MARK: - Lock state

@Test func startsFromTheSessionState() {
    #expect(LockMonitor(isLockedNow: { true }).locked)
    #expect(!LockMonitor(isLockedNow: { false }).locked)
}

@Test func recheckCorrectsState() {
    // The lock notification can fire when a screen saver merely starts; the session says unlocked.
    var sessionLocked = false
    let monitor = LockMonitor(isLockedNow: { sessionLocked })
    var changes: [Bool] = []
    monitor.onChange = { changes.append($0) }

    monitor.notificationArrived(locked: true)
    #expect(monitor.locked)
    monitor.recheck()
    #expect(!monitor.locked)
    #expect(changes == [true, false])

    // …and the Mac really locks later with no second notification: the next recheck catches it.
    sessionLocked = true
    monitor.recheck()
    #expect(monitor.locked)
    monitor.recheck()                       // no change, no extra callback
    #expect(changes == [true, false, true])
}

// MARK: - Photo slices

private func quadrantPhoto(width: Int, height: Int) -> CGImage {
    // Upright quadrants: top-left red, top-right blue, bottom-left green, bottom-right yellow.
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let w = CGFloat(width) / 2, h = CGFloat(height) / 2
    ctx.setFillColor(red: 0, green: 1, blue: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))   // bottom-left (y up)
    ctx.setFillColor(red: 1, green: 1, blue: 0, alpha: 1); ctx.fill(CGRect(x: w, y: 0, width: w, height: h))   // bottom-right
    ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: h, width: w, height: h))   // top-left
    ctx.setFillColor(red: 0, green: 0, blue: 1, alpha: 1); ctx.fill(CGRect(x: w, y: h, width: w, height: h))   // top-right
    return ctx.makeImage()!
}

@Test func slicesCoverRects() {
    for (w, h) in [(1600, 480), (400, 800), (800, 480)] {
        let slices = LockPhoto.slices(quadrantPhoto(width: w, height: h), rects: LockPhoto.n4Rects)
        #expect(Set(slices.keys) == Set(LockPhoto.n4Rects.keys))
        for (slot, rect) in LockPhoto.n4Rects {
            #expect(slices[slot]?.width == Int(rect.width) && slices[slot]?.height == Int(rect.height))
        }
    }
    #expect(LockPhoto.n4Rects.keys.sorted() == [1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15])
}

@Test func quadrantsLandInTheRightSlices() {
    let slices = LockPhoto.slices(quadrantPhoto(width: 800, height: 480), rects: LockPhoto.n4Rects)
    func centre(_ slot: UInt8) -> (r: Int, g: Int, b: Int) {
        let img = slices[slot]!
        return pixel(img, img.width / 2, img.height / 2)
    }
    let key1 = centre(11), key5 = centre(15), strip1 = centre(1), strip4 = centre(4)
    #expect(key1.r > 200 && key1.g < 60 && key1.b < 60)       // top-left key: red
    #expect(key5.b > 200 && key5.r < 60)                      // top-right key: blue
    #expect(strip1.g > 200 && strip1.r < 60)                  // strip, left: green
    #expect(strip4.r > 200 && strip4.g > 200 && strip4.b < 60) // strip, right: yellow
}

@Test func slicesAreTurned180() {
    // A slice straddling the photo's left/right boundary shows the right side's colour on its left.
    let rect = CGRect(x: 350, y: 100, width: 100, height: 100)   // spans x = 400 (red | blue), top half
    let slice = LockPhoto.slices(quadrantPhoto(width: 800, height: 480), rects: [1: rect])[1]!
    let left = pixel(slice, 10, 50), right = pixel(slice, 90, 50)
    #expect(left.b > 200 && left.r < 60)     // blue (photo's right) now on the left
    #expect(right.r > 200 && right.b < 60)
}
