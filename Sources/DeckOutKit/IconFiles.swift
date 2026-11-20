import AppKit
import CryptoKit
import Foundation
import ImageIO

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

    public enum ImportError: Error, Equatable, CustomStringConvertible {
        case notAnImage
        case notSaved

        public var description: String {
            switch self {
            case .notAnImage: return "That file isn't a picture DeckOut can read."
            case .notSaved: return "The picture couldn't be saved in DeckOut's folder."
            }
        }
    }

    /// The image at `source`, decoded and made at most 512 px on a side (the deck refuses anything over 1024, and a
    /// key is 112), saved as a PNG named for its contents: `icons/image-<hash>.png`. Throws for a file that isn't an
    /// image (or isn't there).
    public static func importImage(from source: String, folder: String) throws -> String {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
        ]
        guard let imageSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: source) as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw ImportError.notAnImage }
        let path = folder + "/image-\(hash(png)).png"
        guard write(png, to: path, folder: folder) else { throw ImportError.notSaved }
        return path
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

    /// Writes a new file at 0600 from the start (a temp file created 0600, then renamed over), making the folder
    /// 0700 if needed; true on success.
    private static func write(_ data: Data, to path: String, folder: String) -> Bool {
        do {
            if !FileManager.default.fileExists(atPath: folder) {
                try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
            }
        } catch {
            return false
        }
        let temp = folder + "/.\(UUID().uuidString).tmp"
        let fd = open(temp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return false }
        let written = data.withUnsafeBytes { buffer -> Bool in
            var offset = 0
            while offset < buffer.count {
                let n = Darwin.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if n <= 0 { return false }
                offset += n
            }
            return true
        }
        close(fd)
        guard written, rename(temp, path) == 0 else {
            unlink(temp)
            return false
        }
        return true
    }

    private static func hash(_ string: String) -> String { hash(Data(string.utf8)) }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
