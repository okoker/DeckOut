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
            // Lines as typed (any line break, \r\n included), blank ones dropped.
            let paragraphs = (tile.text ?? "").split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !paragraphs.isEmpty else { return nil }
            drawText(paragraphs, in: ctx, color: foreground)
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

    /// Up to three lines in the rounded bold system font, as large as fits: words wrap at spaces before the size
    /// shrinks, and the size never goes below a readable minimum; what still doesn't fit ends in an ellipsis (never
    /// clipped). Lines are centred across, and the block on the capitals' height, so a single "A" sits in the middle.
    private static func drawText(_ paragraphs: [String], in ctx: CGContext, color: CGColor) {
        let side = CGFloat(size), box = side * fill
        func font(_ size: CGFloat) -> CTFont {
            let base = NSFont.systemFont(ofSize: size, weight: .bold)
            let rounded = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) }
            return (rounded ?? base) as CTFont
        }
        func line(_ text: String, _ font: CTFont) -> CTLine {
            CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
        }
        func width(_ text: String, _ font: CTFont) -> CGFloat {
            CGFloat(CTLineGetTypographicBounds(line(text, font), nil, nil, nil))
        }
        /// Each typed line wrapped at spaces to the box's width (a word wider than the box stays whole).
        func wrap(_ font: CTFont) -> [String] {
            paragraphs.flatMap { paragraph -> [String] in
                var lines: [String] = [], current = ""
                for word in paragraph.split(separator: " ").map(String.init) {
                    let candidate = current.isEmpty ? word : current + " " + word
                    if current.isEmpty || width(candidate, font) <= box {
                        current = candidate
                    } else {
                        lines.append(current)
                        current = word
                    }
                }
                return current.isEmpty ? lines : lines + [current]
            }
        }
        let largest: CGFloat = paragraphs.count == 1 && paragraphs[0].count <= 2 ? 150 : 110
        let smallest: CGFloat = 30          // ~13 px on the N4's key: still readable
        var size = largest
        var lines = wrap(font(size))
        while size > smallest {
            let f = font(size)
            if lines.count <= 3, lines.allSatisfy({ width($0, f) <= box }), CGFloat(lines.count) * size * 1.12 <= box { break }
            size -= 2
            lines = wrap(font(size))
        }
        let f = font(size)
        let ellipsis = line("…", f)
        var shown = Array(lines.prefix(3))
        if lines.count > 3 { shown[2] += " …" }
        let ctLines: [CTLine] = shown.map { text in
            let full = line(text, f)
            return width(text, f) <= box ? full : (CTLineCreateTruncatedLine(full, Double(box), .end, ellipsis) ?? full)
        }
        let cap = CTFontGetCapHeight(f), lineHeight = size * 1.12
        var baseline = side / 2 + (CGFloat(ctLines.count - 1) * lineHeight + cap) / 2 - cap
        for ctLine in ctLines {
            let advance = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
            ctx.textPosition = CGPoint(x: side / 2 - advance / 2, y: baseline)
            CTLineDraw(ctLine, ctx)
            baseline -= lineHeight
        }
    }

    /// The symbol centred on its own outline (Phosphor's glyphs don't sit in the middle of their advance box).
    private static func drawSymbol(_ character: String, font: CTFont, in ctx: CGContext, color: CGColor) {
        let side = CGFloat(size)
        var unichars = Array(character.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: unichars.count)
        guard CTFontGetGlyphsForCharacters(font, &unichars, &glyphs, unichars.count), let glyph = glyphs.first,
              let outline = CTFontCreatePathForGlyph(font, glyph, nil) else { return }
        let bounds = outline.boundingBoxOfPath
        var position = CGPoint(x: side / 2 - bounds.midX, y: side / 2 - bounds.midY)
        ctx.setFillColor(color)
        CTFontDrawGlyphs(font, [glyph], &position, 1, ctx)
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
