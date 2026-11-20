import AppKit
import DeckCore
import Testing
@testable import DeckOutKit

private func decode(_ png: Data) throws -> CGImage {
    try #require(NSBitmapImageRep(data: png)?.cgImage)
}

/// RGB at a pixel, read as sRGB bytes (the tile's own space); top-left origin.
private func srgb(_ image: CGImage, _ x: CGFloat, _ y: CGFloat) -> (r: Int, g: Int, b: Int) {
    let w = image.width, h = image.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let i = (Int(y) * w + Int(x)) * 4
    return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
}

/// Every pixel in a band along the edges is the background: nothing drawn is cut off.
private func edgesAreBackground(_ image: CGImage, _ bg: (r: Int, g: Int, b: Int), band: Int = 6) -> Bool {
    for i in stride(from: 0, to: image.width, by: 4) {
        for d in 0..<band {
            for (x, y) in [(i, d), (i, image.height - 1 - d), (d, i), (image.width - 1 - d, i)] {
                let p = srgb(image, CGFloat(x), CGFloat(y))
                if abs(p.r - bg.r) > 12 || abs(p.g - bg.g) > 12 || abs(p.b - bg.b) > 12 { return false }
            }
        }
    }
    return true
}

private func centreHas(_ image: CGImage, where match: ((r: Int, g: Int, b: Int)) -> Bool) -> Bool {
    for y in stride(from: 64, to: 192, by: 3) {
        for x in stride(from: 64, to: 192, by: 3) where match(srgb(image, CGFloat(x), CGFloat(y))) { return true }
    }
    return false
}

@Test func textFitsAndContrasts() throws {   // T-141
    let teal = (r: 0x0F, g: 0x8A, b: 0x7E)
    func tile(_ text: String, _ background: String = "#0F8A7E", foreground: String? = nil) -> IconTile {
        IconTile(kind: .text, text: text, symbol: nil, style: nil, background: background, foreground: foreground)
    }
    // One character, a long line, three lines: drawn, white on a dark colour, never cut off.
    for text in ["A", "Standup with the design team", "Stand\nup\nnow"] {
        let image = try decode(try #require(TileRenderer.render(tile(text), library: nil)))
        #expect(image.width == 256 && image.height == 256)
        #expect(edgesAreBackground(image, teal), "\(text.debugDescription) stays inside the tile")
        #expect(centreHas(image) { $0.r > 220 && $0.g > 220 && $0.b > 220 }, "\(text.debugDescription) is white on teal")
    }
    // On yellow, the text is near-black; a chosen colour wins.
    let onYellow = try decode(try #require(TileRenderer.render(tile("Hi", "#FFD60A"), library: nil)))
    #expect(centreHas(onYellow) { $0.r < 70 && $0.g < 70 && $0.b < 70 })
    let red = try decode(try #require(TileRenderer.render(tile("Hi", "#FFD60A", foreground: "#FF0000"), library: nil)))
    #expect(centreHas(red) { $0.r > 200 && $0.g < 60 && $0.b < 60 })
    // Nothing to show: no tile.
    #expect(TileRenderer.render(tile("  \n "), library: nil) == nil)
    #expect(TileRenderer.render(tile("A", "teal"), library: nil) == nil)          // not a colour
}

@Test func symbolDraws() throws {   // T-142
    let library = try #require(SymbolLibrary(folder: resourcesFolder))
    for style in ["bold", "fill"] {
        let tile = IconTile(kind: .symbol, text: nil, symbol: "speaker-high", style: style, background: "#3A3A3C", foreground: nil)
        let image = try decode(try #require(TileRenderer.render(tile, library: library)))
        #expect(edgesAreBackground(image, (0x3A, 0x3A, 0x3C)))
        #expect(centreHas(image) { $0.r > 220 && $0.g > 220 }, "\(style) symbol drawn in white")
    }
    let unknown = IconTile(kind: .symbol, text: nil, symbol: "no-such-icon", style: "bold", background: "#3A3A3C", foreground: nil)
    #expect(TileRenderer.render(unknown, library: library) == nil)
    // Written once per look: the same tile → the same file.
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deckout-tiles-\(UUID().uuidString)").path
    let tile = IconTile(kind: .symbol, text: nil, symbol: "acorn", style: "fill", background: "#0A84FF", foreground: nil)
    let first = try #require(IconFiles.tile(tile, library: library, folder: folder))
    #expect(first.hasPrefix(folder + "/tile-") && first.hasSuffix(".png"))
    #expect(IconFiles.tile(tile, library: library, folder: folder) == first)
}


@Test func tilesForALook() throws {   // T-141 (design check): a strip of sample tiles
    let library = try #require(SymbolLibrary(folder: resourcesFolder))
    let tiles = [
        IconTile(kind: .text, text: "Standup\nZoom", symbol: nil, style: nil, background: "#0F8A7E", foreground: nil),
        IconTile(kind: .text, text: "⌘⇧4", symbol: nil, style: nil, background: "#3A3A3C", foreground: nil),
        IconTile(kind: .text, text: "Backup", symbol: nil, style: nil, background: "#C35A00", foreground: nil),
        IconTile(kind: .symbol, text: nil, symbol: "lightbulb", style: "fill", background: "#5E5CE6", foreground: nil),
        IconTile(kind: .symbol, text: nil, symbol: "music-notes", style: "bold", background: "#FA233B", foreground: nil),
        IconTile(kind: .text, text: "B", symbol: nil, style: nil, background: "#FFD60A", foreground: nil),
    ]
    let ctx = try #require(CGContext(data: nil, width: 6 * 140, height: 140, bitsPerComponent: 8, bytesPerRow: 6 * 140 * 4,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    for (i, tile) in tiles.enumerated() {
        let image = try decode(try #require(TileRenderer.render(tile, library: library)))
        ctx.draw(image, in: CGRect(x: i * 140 + 14, y: 14, width: 112, height: 112))   // at the N4's key size
    }
    let strip = try #require(ctx.makeImage())
    try #require(NSBitmapImageRep(cgImage: strip).representation(using: .png, properties: [:]))
        .write(to: snapshotFolder.appendingPathComponent("tiles.png"))
}
