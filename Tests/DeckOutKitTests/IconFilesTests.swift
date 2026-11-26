import AppKit
import DeckCore
import Foundation
import Testing
@testable import DeckOutKit

private func tempFolder() throws -> String {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("deckout-icons-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.appendingPathComponent("icons").path
}

@Test func appIconAndCopiedImageLandInIcons() throws {   // T-127
    let folder = try tempFolder()
    let notes = "/System/Applications/Notes.app"
    let icon = try #require(IconFiles.appIcon(appPath: notes, folder: folder))
    #expect(icon.hasPrefix(folder + "/app-"))
    #expect(icon.hasSuffix(".png"))
    let image = try #require(NSImage(contentsOfFile: icon)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
    #expect(image.width == 256 && image.height == 256)
    var st = stat()
    lstat(icon, &st)
    #expect(st.st_mode & 0o777 == 0o600)
    lstat(folder, &st)
    #expect(st.st_mode & 0o777 == 0o700)
    // The same app again: the same file.
    #expect(IconFiles.appIcon(appPath: notes, folder: folder) == icon)

    // A chosen image is imported: decoded, at most 512 px on a side, saved as a PNG (a phone photo would be refused
    // by the deck at over 1024 px); the original can go.
    let big = try writeBigPNG(side: 2000)
    let imported = try IconFiles.importImage(from: big, folder: folder)
    #expect(imported.hasPrefix(folder + "/image-") && imported.hasSuffix(".png"))
    let decoded = try #require(NSImage(contentsOfFile: imported)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
    #expect(max(decoded.width, decoded.height) == 512)
    #expect(DeckPreview.keyImage(path: imported, deck: .n4) != nil)
    lstat(imported, &st)
    #expect(st.st_mode & 0o777 == 0o600)

    // Not an image: refused with a message, nothing written.
    let text = FileManager.default.temporaryDirectory.appendingPathComponent("deckout-src-\(UUID().uuidString).png").path
    try Data("not a picture".utf8).write(to: URL(fileURLWithPath: text))
    #expect(throws: IconFiles.ImportError.notAnImage) { try IconFiles.importImage(from: text, folder: folder) }
    #expect(throws: IconFiles.ImportError.notAnImage) { try IconFiles.importImage(from: "/nonexistent.png", folder: folder) }
}

private func writeBigPNG(side: Int) throws -> String {
    let ctx = try #require(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.setFillColor(red: 0.2, green: 0.6, blue: 1, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
    let rep = NSBitmapImageRep(cgImage: try #require(ctx.makeImage()))
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("deckout-big-\(UUID().uuidString).png").path
    try #require(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
    return path
}

@Test func editsReachTheLivePreset() {   // T-128
    var config = AppConfig.empty
    // A deck with no section yet gets one ("Default" preset, brightness 75) on its first edit.
    config.setButton(.n4, "key_3", ButtonConfig(action: "media_play_pause"))
    #expect(config.n4?.activePreset == "Default")
    #expect(config.n4?.brightness == 75)
    #expect(config.button(.n4, "key_3")?.action == "media_play_pause")

    // Edits land in the live preset only.
    config.n4?.presets.append(N4Preset(name: "Music", keys: [:], strip: [:]))
    config.n4?.activePreset = "Music"
    config.setButton(.n4, "key_3", ButtonConfig(action: "media_next"))
    #expect(config.n4?.presets[0].keys["key_3"]?.action == "media_play_pause")
    #expect(config.n4?.presets[1].keys["key_3"]?.action == "media_next")
    config.setButton(.n4, "key_3", nil)
    #expect(config.n4?.presets[1].keys["key_3"] == nil)

    config.setStripBlock("3", StripBlockConfig(type: .load))        // block 3: empty in the baseline Default
    #expect(config.stripBlock("3")?.type == .load)
    #expect(config.n4?.presets[0].strip["3"] == nil)

    // Knobs belong to the deck, not a preset.
    config.setKnob(.n3, "big", KnobConfig(rotate: KnobAction(action: "system_volume", step: 2), press: KnobAction(action: "system_mute_toggle")))
    #expect(config.knob(.n3, "big")?.rotate.step == 2)
    #expect(config.n3?.presets.count == 1)
    config.setButton(.n3, "btn_2", ButtonConfig(action: "media_previous"))
    #expect(config.button(.n3, "btn_2")?.action == "media_previous")
}
