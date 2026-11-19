import CoreGraphics
import Foundation
import ImageIO
import Testing

/// A deck input report as macOS delivers it (no report-ID byte):
/// "ACK\0\0OK\0\0", then the event code (byte 9) and state (byte 10).
func ackReport(_ code: UInt8, _ state: UInt8) -> [UInt8] {
    [0x41, 0x43, 0x4B, 0x00, 0x00, 0x4F, 0x4B, 0x00, 0x00, code, state]
}

/// Repository root, found from this file's location (Tests/DeckCoreTests/TestSupport.swift).
let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// Writes a PNG drawn by `draw` (CG coordinates, y up) to a fresh temporary file.
func writePNG(width: Int, height: Int, _ draw: (CGContext) -> Void) throws -> String {
    let ctx = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    draw(ctx)
    let image = try #require(ctx.makeImage())
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("deckcore-test-\(UUID().uuidString).png")
    let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(dest, image, nil)
    #expect(CGImageDestinationFinalize(dest))
    return url.path
}

/// Decodes JPEG (or any image) data.
func decodeImage(_ data: Data) throws -> CGImage {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
}

/// RGB of one pixel, `y` counted from the top row.
func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
    let w = image.width, h = image.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let i = (y * w + x) * 4
    return (Int(buf[i]), Int(buf[i + 1]), Int(buf[i + 2]))
}

/// A picture whose top half is red and bottom half blue, for checking the 180° turn.
func redTopBlueBottomPNG(width: Int = 100, height: Int = 100) throws -> String {
    try writePNG(width: width, height: height) { ctx in
        ctx.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))            // bottom (y up)
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: height / 2, width: width, height: height / 2))   // top
    }
}
