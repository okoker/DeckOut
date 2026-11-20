import AppKit
import CoreText
import DeckCore

/// Draws generated key icons: text, or a library symbol, on a colour, edge to edge, 256 × 256 PNG. The deck shrinks
/// it to its key (112 or 85 px), so text is set large and bold.
public enum TileRenderer {
    public static let size = 256
    /// Text and symbols keep inside this share of the tile.
    private static let fill: CGFloat = 0.82

    public static func render(_ tile: IconTile, library: SymbolLibrary?) -> Data? {
        guard let background = color(hex: tile.background) else { return nil }
        let foreground = tile.foreground.flatMap(color(hex:)) ?? readable(on: background)
        let side = CGFloat(size)
        // sRGB, so the saved colour is the one picked (#RRGGBB means sRGB).
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(background)
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))

        switch tile.kind {
        case .text:
            let lines = (tile.text ?? "").split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let shown = Array(lines.drop { $0.isEmpty }.reversed().drop { $0.isEmpty }.reversed().prefix(3))
            guard !shown.isEmpty else { return nil }
            drawText(shown, in: ctx, color: foreground)
        case .symbol:
            guard let library, let name = tile.symbol, let character = library.character(name) else { return nil }
            let style = SymbolLibrary.Style(rawValue: tile.style ?? "bold") ?? .bold
            drawSymbol(character, font: library.font(style, size: side * 0.62), in: ctx, color: foreground)
        }
        guard let image = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// `#RRGGBB` → colour; nil for anything else.
    public static func color(hex: String) -> CGColor? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return CGColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    /// White on a dark colour, near-black on a light one (relative luminance).
    public static func readable(on background: CGColor) -> CGColor {
        let c = background.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?
            .components ?? [0, 0, 0]
        func linear(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(c[0]) + 0.7152 * linear(c[1]) + 0.0722 * linear(c[2])
        return luminance > 0.45 ? CGColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
                                : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    }

    // MARK: - Drawing

    /// Up to three lines, centred, in the rounded bold system font, as large as fits.
    private static func drawText(_ lines: [String], in ctx: CGContext, color: CGColor) {
        let side = CGFloat(size), box = side * fill
        func font(_ size: CGFloat) -> CTFont {
            let base = NSFont.systemFont(ofSize: size, weight: .bold)
            let rounded = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) }
            return (rounded ?? base) as CTFont
        }
        func ctLines(_ size: CGFloat) -> [CTLine] {
            lines.map { line in
                let attributes: [NSAttributedString.Key: Any] = [.font: font(size), .foregroundColor: color]
                return CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: attributes))
            }
        }
        // Start large (one short word fills the key), shrink until every line fits the box.
        var size: CGFloat = lines.count == 1 && lines[0].count <= 2 ? 150 : 110
        var set = ctLines(size)
        while size > 10 {
            let widest = set.map { CTLineGetBoundsWithOptions($0, .useGlyphPathBounds).width }.max() ?? 0
            let height = CGFloat(set.count) * size * 1.12
            if widest <= box && height <= box { break }
            size -= 2
            set = ctLines(size)
        }
        let lineHeight = size * 1.12
        let top = side / 2 + CGFloat(set.count) * lineHeight / 2
        for (index, line) in set.enumerated() {
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            let baseline = top - CGFloat(index + 1) * lineHeight + (lineHeight - size) / 2 + size * 0.22
            ctx.textPosition = CGPoint(x: side / 2 - bounds.midX, y: baseline)
            CTLineDraw(line, ctx)
        }
    }

    /// The symbol centred by its own outline (optical centre), not its advance box.
    private static func drawSymbol(_ character: String, font: CTFont, in ctx: CGContext, color: CGColor) {
        let side = CGFloat(size)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: character, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        ctx.textPosition = CGPoint(x: side / 2 - bounds.midX, y: side / 2 - bounds.midY)
        CTLineDraw(line, ctx)
    }
}

extension IconFiles {
    /// The tile rendered and written as `icons/tile-<hash of the picture>.png`; the same look, the same file.
    public static func tile(_ tile: IconTile, library: SymbolLibrary?, folder: String) -> String? {
        guard let png = TileRenderer.render(tile, library: library) else { return nil }
        let path = folder + "/tile-\(contentHash(png)).png"
        if FileManager.default.fileExists(atPath: path) { return path }
        return writeFile(png, to: path, folder: folder) ? path : nil
    }
}
