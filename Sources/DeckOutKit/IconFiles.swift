import AppKit
import CryptoKit
import DeckCore
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
        case tooLarge

        public var description: String {
            switch self {
            case .notAnImage: return "That file isn't a picture DeckOut can read."
            case .notSaved: return "The picture couldn't be saved in DeckOut's folder."
            case .tooLarge: return "That file is too large for a lock photo (over 100 MB). Pick a smaller one."
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

    /// The N4's lock photo, saved in the config folder at most 3200 px on a side as a JPEG (the agent decodes it on
    /// every lock; the face is 800 × 464, so zoom has room): `<config folder>/lock-photo-<hash>.jpg`. Read through
    /// ImageIO, never whole into memory; a file over `maxBytes` is refused before it's read; one that isn't a
    /// picture is refused.
    public static func importLockPhoto(from source: String, configPath: String, maxBytes: Int = 100_000_000) throws -> String {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: source))?[.size] as? Int else {
            throw ImportError.notAnImage
        }
        guard size <= maxBytes else { throw ImportError.tooLarge }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 3200,
        ]
        guard let imageSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: source) as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary),
              let jpeg = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.92])
        else { throw ImportError.notAnImage }
        let folder = (configPath as NSString).deletingLastPathComponent
        let path = folder + "/lock-photo-\(hash(jpeg)).jpg"
        guard write(jpeg, to: path, folder: folder) else { throw ImportError.notSaved }
        return path
    }

    /// DeckOut's own file names: keys' and blocks' pictures in `icons/`, lock photos beside the config.
    private static let madeIcon = #/(?:app|image|tile)-[0-9a-f]{16}\.png/#
    private static let madeLockPhoto = #/lock-photo-[0-9a-f]{16}\.jpg/#

    /// Removes the files DeckOut made that nothing names any more (BL-018, BL-023), and returns their paths. A file is
    /// kept if its name appears anywhere in any other file in the config folder, subfolders included (the config, its
    /// `.before-app` copy, anything kept beside it): the text is searched, not the config's fields, so an icon can't
    /// be missed for a field this code doesn't know. Only DeckOut's own names in their own places, only plain files
    /// (never a link). Nothing at all when the config is missing or doesn't load, or any other file can't be read.
    /// Run before any edit: the undo history can name files the config doesn't (`AppModel.removeUnusedIcons`).
    @discardableResult
    public static func removeUnused(configPath: String) -> [String] {
        guard case .success = ConfigFile.load(at: configPath) else { return [] }
        let base = (configPath as NSString).deletingLastPathComponent
        let icons = folder(forConfig: configPath)
        let manager = FileManager.default
        func isPlainFile(_ path: String) -> Bool {
            (try? manager.attributesOfItem(atPath: path)[.type] as? FileAttributeType) == .typeRegular
        }
        func made(in folder: String, _ name: Regex<Substring>) -> [String] {
            ((try? manager.contentsOfDirectory(atPath: folder)) ?? [])
                .filter { $0.wholeMatch(of: name) != nil }
                .map { folder + "/" + $0 }
                .filter(isPlainFile)
        }
        let candidates = made(in: icons, madeIcon) + made(in: base, madeLockPhoto)
        guard !candidates.isEmpty else { return [] }
        let skip = Set(candidates)
        var texts: [Data] = []
        for case let relative as String in manager.enumerator(atPath: base) ?? NSEnumerator() {
            let path = base + "/" + relative
            guard !skip.contains(path), isPlainFile(path) else { continue }
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped) else { return [] }
            texts.append(data)
        }
        let unused = candidates.filter { path in
            let name = Data((path as NSString).lastPathComponent.utf8)
            return !texts.contains { $0.range(of: name) != nil }
        }
        return unused.filter { unlink($0) == 0 }
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

    static func contentHash(_ data: Data) -> String { hash(data) }
    static func writeFile(_ data: Data, to path: String, folder: String) -> Bool { write(data, to: path, folder: folder) }

    private static func hash(_ string: String) -> String { hash(Data(string.utf8)) }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
