import DeckCore
import Foundation
import Testing
@testable import DeckOutKit

/// A fresh config folder with an `icons/` folder in it: the config's path and the icons folder.
private func configFolder() throws -> (config: String, icons: String) {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("deckout-cleanup-\(UUID().uuidString)").path
    try FileManager.default.createDirectory(atPath: base + "/icons", withIntermediateDirectories: true)
    return (base + "/config.json", base + "/icons")
}

private func touch(_ path: String) throws { try Data("x".utf8).write(to: URL(fileURLWithPath: path)) }

/// A 16-digit hash, as DeckOut names its files.
private func hex(_ n: Int) -> String { String(format: "%016x", n) }

// Icon files DeckOut made that nothing names any more are removed (BL-018, BL-023: every Choose, colour tap and text
// edit left one for good). Kept: whatever the config names (a key in the live preset or another one, a strip
// picture, the lock photo, an N3 key) and whatever any other file there names (the hand-written config's
// `.before-app` copy, a copy kept in a subfolder). Never touched: files that aren't DeckOut's own (a script's picture, other names, the right
// name in the wrong folder, a temp file) and links.
@Test func unusedIconFilesGo() throws {   // T-186
    let (configPath, icons) = try configFolder()
    let base = (configPath as NSString).deletingLastPathComponent
    let live = icons + "/tile-\(hex(1)).png", other = icons + "/image-\(hex(2)).png"
    let strip = icons + "/app-\(hex(3)).png", photo = base + "/lock-photo-\(hex(4)).jpg"
    let n3 = icons + "/tile-\(hex(5)).png"
    var config = AppConfig(n4: N4Section(
        brightness: 75, swipe: nil, lockPhoto: LockPhotoConfig(path: photo),
        presets: [N4Preset(name: "Work", keys: ["key_1": ButtonConfig(action: "media_next", icon: live)],
                           strip: ["2": StripBlockConfig(type: .picture, icon: strip)]),
                  N4Preset(name: "Music", keys: ["key_2": ButtonConfig(action: "media_next", icon: other)], strip: [:])],
        activePreset: "Work"))
    config.setButton(.n3, "lcd_1", ButtonConfig(action: "media_next", icon: n3))
    try ConfigFile.save(config, to: configPath)
    let backedUp = icons + "/tile-\(hex(6)).png", keptAside = icons + "/tile-\(hex(14)).png"
    try Data("{\"icon\": \"\(backedUp)\"}".utf8).write(to: URL(fileURLWithPath: configPath + ".before-app"))
    try FileManager.default.createDirectory(atPath: base + "/old", withIntermediateDirectories: true)
    try Data("{\"icon\": \"\(keptAside)\"}".utf8).write(to: URL(fileURLWithPath: base + "/old/config.json"))

    let unused = [icons + "/tile-\(hex(7)).png", icons + "/image-\(hex(8)).png", icons + "/app-\(hex(9)).png",
                  base + "/lock-photo-\(hex(10)).jpg"]
    let notOurs = [icons + "/weather.png", icons + "/tile-notes.png", icons + "/tile-\(hex(11)).jpg",
                   icons + "/lock-photo-\(hex(12)).jpg", base + "/tile-\(hex(13)).png", icons + "/.\(UUID()).tmp"]
    for path in [live, other, strip, photo, n3, backedUp, keptAside] + unused + notOurs { try touch(path) }
    let target = base + "/elsewhere.png"
    try touch(target)
    let link = icons + "/tile-\(hex(15)).png"
    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)

    let removed = IconFiles.removeUnused(configPath: configPath)
    #expect(Set(removed) == Set(unused))
    for path in unused { #expect(!FileManager.default.fileExists(atPath: path), "still there: \(path)") }
    for path in [live, other, strip, photo, n3, backedUp, keptAside, target] + notOurs {
        #expect(FileManager.default.fileExists(atPath: path), "removed: \(path)")
    }
    #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link)) == target, "the link stays")
    #expect(IconFiles.removeUnused(configPath: configPath).isEmpty, "a second run finds nothing")
}

// Nothing is removed when the config is missing, doesn't load, or another file in the folder can't be read (it might
// name an icon): the cleanup keeps everything rather than guess.
@Test func noCleanupWithoutAGoodConfig() throws {   // T-187
    let (configPath, icons) = try configFolder()
    let unused = icons + "/tile-\(hex(1)).png"
    try touch(unused)
    #expect(IconFiles.removeUnused(configPath: configPath).isEmpty, "no config")
    try Data("{ not json".utf8).write(to: URL(fileURLWithPath: configPath))
    #expect(IconFiles.removeUnused(configPath: configPath).isEmpty, "a config that doesn't load")
    try FileManager.default.removeItem(atPath: configPath)
    try ConfigFile.save(AppConfig.empty, to: configPath)
    let locked = (configPath as NSString).deletingLastPathComponent + "/notes.txt"
    try touch(locked)
    chmod(locked, 0)
    defer { chmod(locked, 0o600) }
    #expect(IconFiles.removeUnused(configPath: configPath).isEmpty, "a file that can't be read")
    #expect(FileManager.default.fileExists(atPath: unused))
}

// The app cleans up once, at start-up, before any edit: the window's start-up runs again when the window is closed and
// opened, and by then the undo history may name files the config doesn't (undo would bring back a black key).
@MainActor @Test func cleanupRunsOnceBeforeAnyEdit() throws {   // T-188
    let model = try previewModel(AppConfig.empty, deck: .n4, selection: "key_1")
    let store = try #require(model.store)
    let icons = IconFiles.folder(forConfig: store.path)
    try FileManager.default.createDirectory(atPath: icons, withIntermediateDirectories: true)
    let first = icons + "/tile-\(hex(1)).png"
    try touch(first)
    model.setAction(.runCommand("echo hi"), button: "key_1", on: .n4)
    model.removeUnusedIcons()
    #expect(FileManager.default.fileExists(atPath: first), "an edit is in the undo history: nothing removed")

    let fresh = try previewModel(AppConfig.empty, deck: .n4, selection: nil)
    let freshIcons = IconFiles.folder(forConfig: try #require(fresh.store).path)
    try FileManager.default.createDirectory(atPath: freshIcons, withIntermediateDirectories: true)
    let unused = freshIcons + "/tile-\(hex(2)).png"
    try touch(unused)
    fresh.removeUnusedIcons()
    #expect(!FileManager.default.fileExists(atPath: unused), "removed at start-up")
    let later = freshIcons + "/tile-\(hex(3)).png"
    try touch(later)
    fresh.removeUnusedIcons()
    #expect(FileManager.default.fileExists(atPath: later), "once per run")
}
