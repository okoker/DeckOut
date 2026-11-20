import CoreGraphics
import Foundation
import ImageIO

/// A photo shown across the N4 while the Mac is locked. The keys and the strip are windows onto one
/// picture: the photo is scaled to fill the deck's face, then zoomed and moved as its framing says, each slot's rectangle is cut
/// out at its position and turned 180°, and the pieces are sent like icons. Nothing is stored on the deck.
public enum LockPhoto {
    /// The deck's face in key-image pixels: the bounding box of the 14 screens.
    public static let canvas = CGSize(width: 800, height: 464)

    /// Slot → rectangle on the face, top-left origin, as seen by the user. Measured on the N4 19/11/2026
    /// from a photo of a test grid (one key-image pixel ≈ 1.35 photo pixels): keys 112×112 at 172 apart,
    /// rows 176 apart; strip blocks 176×112 at 208 apart, 352 below the top row, as wide as the key block.
    public static let n4Rects: [UInt8: CGRect] = {
        var rects: [UInt8: CGRect] = [:]
        for column in 0..<5 {
            let x = CGFloat(172 * column)
            rects[UInt8(11 + column)] = CGRect(x: x, y: 0, width: 112, height: 112)      // top row: key_1–key_5
            rects[UInt8(6 + column)] = CGRect(x: x, y: 176, width: 112, height: 112)     // bottom row: key_6–key_10
        }
        for block in 0..<4 {
            rects[UInt8(1 + block)] = CGRect(x: CGFloat(208 * block), y: 352, width: 176, height: 112)
        }
        return rects
    }()

    /// Loads the photo, downscaled on decode (a phone photo is ~4000 px; nothing larger than the panel
    /// is needed) and turned upright per its EXIF orientation. Nil, with a log line, if unreadable.
    public static func load(path: String) -> CGImage? {
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

    /// Where the photo sits on the face, top-left origin, as the user sees it: aspect-fill, then `zoom` about the
    /// centre, then the offsets (fractions of the face), then clamped so the photo covers the whole face.
    public static func placement(photo: CGSize, framing: LockPhotoConfig) -> CGRect {
        let fill = aspectFill(photo, in: CGRect(origin: .zero, size: canvas))
        let zoom = CGFloat(framing.zoom.isFinite ? max(1, framing.zoom) : 1)
        // max(): rounding in the fill must never leave a sliver of the face uncovered.
        let w = max(fill.width * zoom, canvas.width), h = max(fill.height * zoom, canvas.height)
        let dx = CGFloat(framing.offsetX.isFinite ? framing.offsetX : 0) * canvas.width
        let dy = CGFloat(framing.offsetY.isFinite ? framing.offsetY : 0) * canvas.height
        let x = min(0, max(canvas.width - w, (canvas.width - w) / 2 + dx))
        let y = min(0, max(canvas.height - h, (canvas.height - h) / 2 + dy))
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// The framed photo on the deck's face, upright, 800 × 464: what the app draws, and what `slices` cuts.
    public static func panel(_ photo: CGImage, framing: LockPhotoConfig?) -> CGImage? {
        let width = Int(canvas.width), height = Int(canvas.height)
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        let rect = placement(photo: CGSize(width: photo.width, height: photo.height),
                             framing: framing ?? LockPhotoConfig(path: ""))
        // CG draws with y up: flip the top-left placement.
        ctx.draw(photo, in: CGRect(x: rect.minX, y: canvas.height - rect.maxY, width: rect.width, height: rect.height))
        return ctx.makeImage()
    }

    /// How far the offsets can go at `zoom` before the photo stops moving (it always covers the face): fractions of
    /// the face's width and height, either way.
    public static func offsetLimits(photo: CGSize, zoom: Double) -> (x: Double, y: Double) {
        let fill = aspectFill(photo, in: CGRect(origin: .zero, size: canvas))
        let z = CGFloat(zoom.isFinite ? min(10, max(1, zoom)) : 1)
        let w = max(fill.width * z, canvas.width), h = max(fill.height * z, canvas.height)
        return (Double((w - canvas.width) / (2 * canvas.width)), Double((h - canvas.height) / (2 * canvas.height)))
    }

    /// The framing with zoom kept to 1…10 and the offsets to their limits: the photo sits where it did, and a drag
    /// back moves it at once instead of first working off offset that went past the edge.
    public static func clamped(_ framing: LockPhotoConfig, photo: CGSize) -> LockPhotoConfig {
        let zoom = framing.zoom.isFinite ? min(10, max(1, framing.zoom)) : 1
        let limits = offsetLimits(photo: photo, zoom: zoom)
        func clamp(_ value: Double, _ limit: Double) -> Double {
            value.isFinite ? min(limit, max(-limit, value)) : 0
        }
        return LockPhotoConfig(path: framing.path, zoom: zoom, offsetX: clamp(framing.offsetX, limits.x),
                               offsetY: clamp(framing.offsetY, limits.y))
    }

    /// The decoded photo while the app's preview is up: a drag sends a framing per move, and decoding a phone photo
    /// each time would lag. Holds one photo, by path.
    public final class PreviewCache {
        private let loader: (String) -> CGImage?
        private var cached: (path: String, image: CGImage)?

        public init(load: @escaping (String) -> CGImage? = LockPhoto.load(path:)) {
            loader = load
        }

        public func image(for path: String) -> CGImage? {
            if let cached, cached.path == path { return cached.image }
            guard let image = loader(path) else { return nil }
            cached = (path, image)
            return image
        }

        public func clear() { cached = nil }
    }

    /// The photo cut into one piece per rectangle, each turned 180° for the deck. No framing: filled and centred.
    static func slices(_ photo: CGImage, rects: [UInt8: CGRect], framing: LockPhotoConfig? = nil) -> [UInt8: CGImage] {
        guard let panel = panel(photo, framing: framing) else { return [:] }
        var result: [UInt8: CGImage] = [:]
        for (slot, rect) in rects {
            guard let piece = panel.cropping(to: rect),          // CGImage cropping: top-left origin
                  let turned = turn180(piece) else { continue }
            result[slot] = turned
        }
        return result
    }

    /// Every slice of the framed photo as a JPEG, ready to send.
    static func jpegSlices(_ framing: LockPhotoConfig, rects: [UInt8: CGRect] = n4Rects, photo given: CGImage? = nil) -> [UInt8: Data] {
        guard let photo = given ?? load(path: framing.path) else { return [:] }
        return slices(photo, rects: rects, framing: framing).compactMapValues { Canvas.encodeJPEG($0) }
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
