import Foundation

/// Key images for the N4: 112×112 JPEG, turned 180°, no offset (owner's decision, 18/11/2026).
enum IconImage {
    static let n4Size = 112

    /// The icon at `path`, transparent padding trimmed, fitted inside a 4 px margin on black.
    /// Nil when the file is missing or unreadable.
    static func renderN4(path: String) -> Data? {
        Canvas.iconTile(path: path, width: n4Size, height: n4Size)
    }

    /// The same from the icon file's bytes, already read (`path` names it in the log lines and gives its type).
    static func renderN4(data: Data, path: String) -> Data? {
        Canvas.iconTile(data: data, path: path, width: n4Size, height: n4Size)
    }
}
