import CoreGraphics
import Foundation
import ImageIO

/// Drawing helpers for deck images: a black canvas, the 180° turn the N4 needs, JPEG encoding.
/// (The N3 keeps its own pipeline, `ImageLoader.loadAsJPEG`, unchanged.)
enum Canvas {

    /// Renders a `width`×`height` JPEG on a black background. `draw` paints in upright
    /// coordinates (CG, y up); with `turn180` the result is rotated so it reads upright on the deck.
    static func jpeg(width: Int, height: Int, turn180: Bool = true, quality: Double = 0.9,
                     draw: (CGContext) -> Void) -> Data? {
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if turn180 {
            ctx.translateBy(x: CGFloat(width), y: CGFloat(height))
            ctx.rotate(by: .pi)
        }
        ctx.interpolationQuality = .high
        draw(ctx)
        guard let image = ctx.makeImage() else { return nil }
        return encodeJPEG(image, quality: quality)
    }

    static func encodeJPEG(_ image: CGImage, quality: Double = 0.9) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.jpeg" as CFString, 1, nil)
        else { return nil }
        let opts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, image, opts as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// Decodes the first image in a file. Nil, with a log line, when the file is missing,
    /// undecodable, or larger than `maxDimension` pixels on a side (icons only — not photos).
    static func loadImage(path: String, maxDimension: Int = 1024) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            print("Warning: could not load image at \(path)")
            return nil
        }
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let pw = props[kCGImagePropertyPixelWidth] as? Int,
           let ph = props[kCGImagePropertyPixelHeight] as? Int,
           pw > maxDimension || ph > maxDimension {
            print("Warning: image too large (\(pw)x\(ph), max \(maxDimension)px) at \(path)")
            return nil
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            print("Warning: could not decode image at \(path)")
            return nil
        }
        return image
    }

    /// The largest rect with `size`'s proportions that fits in `bounds`, centred.
    static func aspectFit(_ size: CGSize, in bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
    }

    /// Loads an icon, trims its transparent padding and draws it fitted inside a black
    /// `width`×`height` tile with `margin` on every side, turned 180°.
    static func iconTile(path: String, width: Int, height: Int, margin: CGFloat = 4) -> Data? {
        guard let source = loadImage(path: path) else { return nil }
        let icon = ImageLoader.trimTransparency(source) ?? source
        let box = CGRect(x: 0, y: 0, width: width, height: height).insetBy(dx: margin, dy: margin)
        let rect = aspectFit(CGSize(width: icon.width, height: icon.height), in: box)
        return jpeg(width: width, height: height) { ctx in ctx.draw(icon, in: rect) }
    }
}
