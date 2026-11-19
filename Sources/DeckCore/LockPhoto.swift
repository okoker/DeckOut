import CoreGraphics
import Foundation
import ImageIO

/// A photo shown across the N4 while the Mac is locked. The keys and the strip are windows onto one
/// 800×480 panel: the photo is scaled to fill the panel (centre-cropped), each slot's rectangle is cut
/// out at its panel position and turned 180°, and the pieces are sent like icons. Nothing is stored on
/// the deck.
enum LockPhoto {
    static let canvas = CGSize(width: 800, height: 480)

    /// Slot → rectangle on the panel, top-left origin, as seen by the user.
    /// STARTING GUESS (calibrated on the device in Task 11): keys on the sibling AKP05E firmware's grid
    /// (x = 5 + 169·column, y = 15 + 174·row, 112×112); strip blocks 176×112 centred under the four
    /// knobs, on the next row (y = 363).
    static let n4Rects: [UInt8: CGRect] = {
        var rects: [UInt8: CGRect] = [:]
        for column in 0..<5 {
            let x = CGFloat(5 + 169 * column)
            rects[UInt8(11 + column)] = CGRect(x: x, y: 15, width: 112, height: 112)    // top row: key_1–key_5
            rects[UInt8(6 + column)] = CGRect(x: x, y: 189, width: 112, height: 112)    // bottom row: key_6–key_10
        }
        for block in 0..<4 {
            rects[UInt8(1 + block)] = CGRect(x: CGFloat(12 + 200 * block), y: 363, width: 176, height: 112)
        }
        return rects
    }()

    /// Loads the photo, downscaled on decode (a phone photo is ~4000 px; nothing larger than the panel
    /// is needed) and turned upright per its EXIF orientation. Nil, with a log line, if unreadable.
    static func load(path: String) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600,
        ]
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            print("Warning: could not load lock photo at \(path)")
            return nil
        }
        return image
    }

    /// The photo cut into one piece per rectangle, each turned 180° for the deck.
    static func slices(_ photo: CGImage, rects: [UInt8: CGRect]) -> [UInt8: CGImage] {
        let width = Int(canvas.width), height = Int(canvas.height)
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [:] }
        ctx.interpolationQuality = .high
        ctx.draw(photo, in: aspectFill(CGSize(width: photo.width, height: photo.height), in: CGRect(origin: .zero, size: canvas)))
        guard let panel = ctx.makeImage() else { return [:] }

        var result: [UInt8: CGImage] = [:]
        for (slot, rect) in rects {
            guard let piece = panel.cropping(to: rect),          // CGImage cropping: top-left origin
                  let turned = turn180(piece) else { continue }
            result[slot] = turned
        }
        return result
    }

    /// Every slice as a JPEG, ready to send.
    static func jpegSlices(path: String, rects: [UInt8: CGRect] = n4Rects) -> [UInt8: Data] {
        guard let photo = load(path: path) else { return [:] }
        return slices(photo, rects: rects).compactMapValues { Canvas.encodeJPEG($0) }
    }

    // MARK: - Private

    private static func aspectFill(_ size: CGSize, in bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = max(bounds.width / size.width, bounds.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
    }

    private static func turn180(_ image: CGImage) -> CGImage? {
        guard let ctx = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.translateBy(x: CGFloat(image.width), y: CGFloat(image.height))
        ctx.rotate(by: .pi)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }
}
