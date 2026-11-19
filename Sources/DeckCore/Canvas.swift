import AppKit
import CoreGraphics
import CoreText
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

// MARK: - Text

extension Canvas {

    /// The system font in its rounded design (falls back to the plain system font).
    static func font(size: CGFloat, weight: NSFont.Weight = .bold) -> CTFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let rounded = base.fontDescriptor.withDesign(.rounded), let font = NSFont(descriptor: rounded, size: size) {
            return font as CTFont
        }
        return base as CTFont
    }

    static func color(_ hex: UInt32) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// One line of text, its glyphs centred on `center` (upright coordinates).
    /// `runs` lets parts of the line use their own size or colour, e.g. a smaller "%".
    static func drawText(_ runs: [(String, CTFont, CGColor)], in ctx: CGContext, center: CGPoint) {
        let text = NSMutableAttributedString()
        for (string, font, color) in runs {
            text.append(NSAttributedString(string: string, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ]))
        }
        let line = CTLineCreateWithAttributedString(text)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: center.x - bounds.midX, y: center.y - bounds.midY)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    static func drawText(_ string: String, in ctx: CGContext, center: CGPoint, font: CTFont, color: CGColor) {
        drawText([(string, font, color)], in: ctx, center: center)
    }
}
