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

/// Every pixel in a band along the edges is the background: nothing drawn is cut off. Any shape of tile.
private func edgesAreBackground(_ image: CGImage, _ bg: (r: Int, g: Int, b: Int), band: Int = 6) -> Bool {
    var points: [(Int, Int)] = []
    for d in 0..<band {
        for x in stride(from: 0, to: image.width, by: 4) { points += [(x, d), (x, image.height - 1 - d)] }
        for y in stride(from: 0, to: image.height, by: 4) { points += [(d, y), (image.width - 1 - d, y)] }
    }
    for (x, y) in points {
        let p = srgb(image, CGFloat(x), CGFloat(y))
        if abs(p.r - bg.r) > 12 || abs(p.g - bg.g) > 12 || abs(p.b - bg.b) > 12 { return false }
    }
    return true
}

/// The box around every near-white pixel (decoded once); nil if there are none.
private func whiteBounds(_ image: CGImage) -> CGRect? {
    let w = image.width, h = image.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h {
        for x in 0..<w {
            let i = (y * w + x) * 4
            guard bytes[i] > 220, bytes[i + 1] > 220, bytes[i + 2] > 220 else { continue }
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    return maxX < 0 ? nil : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
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
        IconTile(kind: .text, text: "Standup with the design team", symbol: nil, style: nil, background: "#30D158", foreground: nil),
        IconTile(kind: .symbol, text: nil, symbol: "play", style: "fill", background: "#3A3A3C", foreground: nil),
    ]
    let ctx = try #require(CGContext(data: nil, width: 8 * 140, height: 140, bitsPerComponent: 8, bytesPerRow: 8 * 140 * 4,
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

@MainActor @Test func tilesOnKeys() throws {   // T-143
    var config = AppConfig.empty
    config.setButton(.n4, "key_1", ButtonConfig(action: "media_next"))
    let model = try previewModel(config, deck: .n4, selection: "key_1")
    let library = try #require(SymbolLibrary(folder: resourcesFolder))
    let tile = IconTile(kind: .symbol, text: nil, symbol: "skip-forward", style: "fill", background: "#0A84FF", foreground: nil)
    model.setTile(tile, button: "key_1", on: .n4, library: library)
    let set = try #require(model.config?.button(.n4, "key_1"))
    #expect(set.tile == tile)
    #expect(set.icon?.contains("/icons/tile-") == true)
    #expect(DeckPreview.keyImage(path: set.icon!, deck: .n4) != nil)
    // Another action keeps the tile; an image (or none) replaces it.
    model.setAction(.playPause, button: "key_1", on: .n4)
    #expect(model.config?.button(.n4, "key_1")?.tile == tile)
    model.setIcon(nil, button: "key_1", on: .n4)
    #expect(model.config?.button(.n4, "key_1")?.tile == nil)
    // A tile that can't be drawn changes nothing and says why.
    let bad = IconTile(kind: .symbol, text: nil, symbol: "no-such", style: "bold", background: "#000000", foreground: nil)
    model.setTile(bad, button: "key_1", on: .n4, library: library)
    #expect(model.config?.button(.n4, "key_1")?.icon == nil)
    #expect(model.iconProblem != nil)
}

/// The drawn ink's bounding box: pixels clearly unlike the background (the image read once, as sRGB bytes).
private func ink(_ image: CGImage, background bg: (r: Int, g: Int, b: Int)) -> CGRect {
    let w = image.width, h = image.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    for y in 0..<h {
        for x in 0..<w {
            let i = (y * w + x) * 4
            if abs(Int(bytes[i]) - bg.r) > 60 || abs(Int(bytes[i + 1]) - bg.g) > 60 || abs(Int(bytes[i + 2]) - bg.b) > 60 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    return maxX < 0 ? .null : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

@Test func symbolsSitInTheMiddle() throws {   // T-142 (review I1)
    let library = try #require(SymbolLibrary(folder: resourcesFolder))
    for name in ["play", "caret-right", "skip-forward", "microphone", "pause"] {
        for style in ["bold", "fill"] {
            let tile = IconTile(kind: .symbol, text: nil, symbol: name, style: style, background: "#000000", foreground: nil)
            let box = ink(try decode(try #require(TileRenderer.render(tile, library: library))), background: (0, 0, 0))
            #expect(abs(box.midX - 128) <= 3, "\(name) \(style) centre x \(box.midX)")
            #expect(abs(box.midY - 128) <= 6, "\(name) \(style) centre y \(box.midY)")
        }
    }
}

@Test func textWrapsStaysReadableAndCentred() throws {   // T-141 (review I2, M8)
    func render(_ text: String) throws -> CGRect {
        let tile = IconTile(kind: .text, text: text, symbol: nil, style: nil, background: "#000000", foreground: "#FFFFFF")
        return ink(try decode(try #require(TileRenderer.render(tile, library: nil))), background: (0, 0, 0))
    }
    // A phrase wraps at its spaces instead of shrinking to a sliver.
    let phrase = try render("Standup with the design team")
    #expect(phrase.height >= 90, "wrapped onto lines: ink height \(phrase.height)")
    #expect(phrase.minX >= 6 && phrase.maxX <= 250)
    // Too long even wrapped: the smallest readable size, cut with an ellipsis, never clipped at the edges.
    for long in [String(repeating: "W", count: 80), String(repeating: "word ", count: 40), "a\nb\nc\nd\ne"] {
        let box = try render(long)
        #expect(box.minX >= 6 && box.maxX <= 250 && box.minY >= 6 && box.maxY <= 250, "\(long.prefix(12)): \(box)")
    }
    // Pasted Windows line endings split like any other.
    let crlf = try render("Stand\r\nup"), oneLine = try render("Standup")
    #expect(crlf.height > oneLine.height)
    // One capital sits in the middle, not high.
    let a = try render("A")
    #expect(abs(a.midY - 128) <= 4, "A centre y \(a.midY)")
    #expect(abs(a.midX - 128) <= 3)
}

@Test func aBrokenTileDoesNotBreakTheConfig() throws {   // T-139 (review M3)
    let json = #"{"decks":{"n4":{"brightness":75,"keys":{"key_1":{"action":"none","icon":"/i.png","tile":{"kind":"emoji"}}}}}}"#
    let config = try AppConfig.parse(Data(json.utf8))
    #expect(config.n4?.keys["key_1"]?.icon == "/i.png")
    #expect(config.n4?.keys["key_1"]?.tile == nil)
}

@Test func defaultTextReadsWell() {   // T-143 (review M1)
    #expect(IconRow.defaultText(.openApp("/System/Applications/Utilities/Activity Monitor.app")) == "Activity Monitor")
    #expect(IconRow.defaultText(.nothing) == "Key")
    #expect(IconRow.defaultText(.playPause) == "Play / Pause")
    #expect(IconRow.defaultText(.openWebsite("https://www.github.com/okoker")) == "github.com")
    // A strip block with no tap starts as "Block", not "Key"; with one, it names it as a key does (T-168).
    #expect(IconRow.defaultText(.nothing, shape: .stripBlock) == "Block")
    #expect(IconRow.defaultText(.playPause, shape: .stripBlock) == "Play / Pause")
    #expect(IconRow.defaultText(.openWebsite("https://www.github.com/okoker"), shape: .stripBlock) == "github.com")
}

@Test func stripTileFillsTheBlock() throws {   // T-156
    let library = try #require(SymbolLibrary(folder: resourcesFolder))
    #expect(TileRenderer.stripWidth == 352 && TileRenderer.stripHeight == 224)   // 2× the block's 176 × 112
    let text = IconTile(kind: .text, text: "Network detail", symbol: nil, style: nil, background: "#0F8A7E", foreground: nil)
    let widePNG = try #require(TileRenderer.render(text, library: nil, width: 352, height: 224))
    let wide = try decode(widePNG)
    #expect(wide.width == 352 && wide.height == 224)
    #expect(edgesAreBackground(wide, (0x0F, 0x8A, 0x7E), band: 13), "nothing within 6 % of an edge")
    // It uses the width: white text both left of x = 88 and right of x = 264.
    let words = try #require(whiteBounds(wide))
    #expect(words.minX < 88 && words.maxX > 264, "text spans \(words)")
    // A symbol sits in the middle of the wide block.
    let symbol = IconTile(kind: .symbol, text: nil, symbol: "cloud-sun", style: "fill", background: "#5E5CE6", foreground: nil)
    let symbolPNG = try #require(TileRenderer.render(symbol, library: library, width: 352, height: 224))
    let mark = try #require(whiteBounds(try decode(symbolPNG)))
    #expect(abs(mark.midX - 176) <= 4 && abs(mark.midY - 112) <= 4, "symbol at \(mark)")
    // A key's tile, by default, is still the 256 square: the text uses its width and stays clear of the edges, the
    // symbol sits in the middle. (Shape, not bytes: font drawing changes with macOS.)
    let key = try decode(try #require(TileRenderer.render(text, library: nil)))
    #expect(key.width == TileRenderer.size && key.height == TileRenderer.size)
    #expect(edgesAreBackground(key, (0x0F, 0x8A, 0x7E), band: 15), "nothing within 6 % of an edge")
    let keyWords = try #require(whiteBounds(key))
    #expect(keyWords.minX < 64 && keyWords.maxX > 192, "key text spans \(keyWords)")
    let keySymbol = try decode(try #require(TileRenderer.render(symbol, library: library)))
    #expect(keySymbol.width == TileRenderer.size && keySymbol.height == TileRenderer.size)
    let keyMark = try #require(whiteBounds(keySymbol))
    #expect(abs(keyMark.midX - 128) <= 4 && abs(keyMark.midY - 128) <= 4, "key symbol at \(keyMark)")
}
