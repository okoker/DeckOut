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

    // A chosen image is copied in, byte for byte; the original can go.
    let source = FileManager.default.temporaryDirectory.appendingPathComponent("deckout-src-\(UUID().uuidString).png").path
    try Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]).write(to: URL(fileURLWithPath: source))
    let copy = try #require(IconFiles.copyImage(from: source, folder: folder))
    #expect(copy.hasPrefix(folder + "/image-") && copy.hasSuffix(".png"))
    #expect(FileManager.default.contents(atPath: copy) == FileManager.default.contents(atPath: source))
    #expect(IconFiles.copyImage(from: "/nonexistent.png", folder: folder) == nil)
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

    config.setStripBlock("2", StripBlockConfig(type: .load))
    #expect(config.stripBlock("2")?.type == .load)
    #expect(config.n4?.presets[0].strip["2"] == nil)

    // Knobs belong to the deck, not a preset.
    config.setKnob(.n3, "big", KnobConfig(rotate: KnobAction(action: "system_volume", step: 2), press: KnobAction(action: "system_mute_toggle")))
    #expect(config.knob(.n3, "big")?.rotate.step == 2)
    #expect(config.n3?.presets.count == 1)
    config.setButton(.n3, "btn_2", ButtonConfig(action: "media_previous"))
    #expect(config.button(.n3, "btn_2")?.action == "media_previous")
}
