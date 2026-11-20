import CoreText
import Foundation
import Testing
@testable import DeckOutKit

/// The repo's `Packaging/Resources` (the app bundle's Resources in a build).
let resourcesFolder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Packaging/Resources")

@Test func indexHasEveryIcon() throws {   // T-140
    let library = try #require(SymbolLibrary(folder: resourcesFolder))
    #expect(library.names.count == 1530)
    #expect(library.code(for: "acorn") == 0xEB9A)
    #expect(library.code(for: "no-such-icon") == nil)
    #expect(library.names.contains("play") && library.names.contains("speaker-high"))
    for style in [SymbolLibrary.Style.bold, .fill] {
        let font = library.font(style, size: 100)
        var glyph = CGGlyph(0)
        var character = UniChar(0xEB9A)
        #expect(CTFontGetGlyphsForCharacters(font, &character, &glyph, 1), "\(style) has the acorn")
    }
}
