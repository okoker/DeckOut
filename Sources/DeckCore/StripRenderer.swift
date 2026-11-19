import Foundation

/// Images for the N4 touch strip: four separate 176×112 JPEG blocks, each turned 180°.
enum StripRenderer {
    static let width = 176
    static let height = 112

    /// A black tile.
    static func blank(w: Int = width, h: Int = height) -> Data {
        Canvas.jpeg(width: w, height: h) { _ in } ?? Data()
    }

    /// A `picture` block: the image at `path`, fitted inside a 4 px margin. Nil if unreadable.
    static func picture(path: String) -> Data? {
        Canvas.iconTile(path: path, width: width, height: height)
    }
}
