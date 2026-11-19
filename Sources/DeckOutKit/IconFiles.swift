import AppKit
import CryptoKit
import Foundation

/// Icons the app makes or copies for the decks. They live in `<config folder>/icons/` (folder 0700, files 0600), so
/// the agent reads them from a folder macOS doesn't guard (Desktop, Documents and Downloads ask first), and moving
/// or deleting an original changes nothing.
public enum IconFiles {

    public static func folder(forConfig configPath: String) -> String {
        (configPath as NSString).deletingLastPathComponent + "/icons"
    }

    /// The app's own icon, as macOS shows it, at 256 px: `icons/app-<hash of the app's path>.png`. Nil when there's
    /// no app there.
    public static func appIcon(appPath: String, folder: String) -> String? {
        guard FileManager.default.fileExists(atPath: appPath) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: appPath)
        guard let png = render(icon, pixels: 256) else { return nil }
        let path = folder + "/app-\(hash(appPath)).png"
        return write(png, to: path, folder: folder) ? path : nil
    }

    /// A copy of the image at `source`, named for its contents: `icons/image-<hash>.<ext>`. Nil if unreadable.
    public static func copyImage(from source: String, folder: String) -> String? {
        guard let data = FileManager.default.contents(atPath: source) else { return nil }
        let ext = (source as NSString).pathExtension.lowercased()
        let path = folder + "/image-\(hash(data)).\(ext.isEmpty ? "png" : ext)"
        return write(data, to: path, folder: folder) ? path : nil
    }

    // MARK: - Private

    private static func render(_ image: NSImage, pixels: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// Writes atomically at 0600, making the folder 0700 if needed; true on success.
    private static func write(_ data: Data, to path: String, folder: String) -> Bool {
        do {
            if !FileManager.default.fileExists(atPath: folder) {
                try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
            }
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            return true
        } catch {
            return false
        }
    }

    private static func hash(_ string: String) -> String { hash(Data(string.utf8)) }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
