import CoreGraphics
import CoreText
import Foundation

/// The built-in icon library: Phosphor 2.1.2 (MIT), its Bold and Fill fonts and a name → character index
/// (`scripts/phosphor-index.swift`), from the app's Resources. Fonts are loaded for the app alone (no system-wide
/// registration).
public final class SymbolLibrary {
    public enum Style: String, CaseIterable { case bold, fill }

    public let names: [String]
    private let codes: [String: UInt32]
    private let fonts: [Style: CGFont]

    public init?(folder: URL) {
        struct Entry: Decodable { let name: String; let code: UInt32 }
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("phosphor-icons.json")),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return nil }
        var fonts: [Style: CGFont] = [:]
        for (style, file) in [(Style.bold, "Phosphor-Bold.ttf"), (.fill, "Phosphor-Fill.ttf")] {
            guard let provider = CGDataProvider(url: folder.appendingPathComponent(file) as CFURL),
                  let font = CGFont(provider) else { return nil }
            fonts[style] = font
        }
        names = entries.map(\.name)
        codes = Dictionary(entries.map { ($0.name, $0.code) }, uniquingKeysWith: { a, _ in a })
        self.fonts = fonts
    }

    /// The app's own copy, from its bundle.
    public static let shared: SymbolLibrary? = Bundle.main.resourceURL.flatMap { SymbolLibrary(folder: $0) }

    public func code(for name: String) -> UInt32? { codes[name] }

    public func font(_ style: Style, size: CGFloat) -> CTFont {
        CTFontCreateWithGraphicsFont(fonts[style]!, size, nil, nil)
    }

    /// The symbol's character as a string, for drawing with `font`.
    public func character(_ name: String) -> String? {
        code(for: name).flatMap { Unicode.Scalar($0) }.map { String(Character($0)) }
    }
}
