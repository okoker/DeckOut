import DeckCore
import Foundation
import Testing
@testable import DeckOutKit

// The app's config store, on a config file in a fresh temp folder.

func tempConfigPath() throws -> String {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("deckout-store-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.appendingPathComponent("config.json").path
}

let storeSample = AppConfig(n4: N4Section(
    brightness: 75, knobs: [:], swipe: nil, lockPhoto: nil,
    presets: [N4Preset(name: "Work", keys: ["key_1": ButtonConfig(action: "url:https://example.com")], strip: [:]),
              N4Preset(name: "Music", keys: [:], strip: [:])],
    activePreset: "Work"))

@MainActor @Test func changeSavesAndReloads() throws {   // T-120
    let path = try tempConfigPath()
    try ConfigFile.save(storeSample, to: path)
    var reloads = 0
    let store = ConfigStore(path: path, reload: { reloads += 1 })
    store.load()
    #expect(store.config == storeSample)

    store.change("Change Brightness") { $0.n4?.brightness = 40 }
    #expect(reloads == 1)
    #expect(try ConfigFile.load(at: path).get().n4?.brightness == 40)
    var st = stat()
    lstat(path, &st)
    #expect(st.st_mode & 0o777 == 0o600)

    // A change that changes nothing saves nothing.
    store.change("Change Brightness") { $0.n4?.brightness = 40 }
    #expect(reloads == 1)

    // A slider dragged across its range: every step saved whole, one reload request each.
    for value in 0...29 { store.change("Change Brightness") { $0.n4?.brightness = value } }
    #expect(reloads == 31)
    #expect(try ConfigFile.load(at: path).get().n4?.brightness == 29)
}

@MainActor @Test func undoRestoresTheWholeConfig() throws {   // T-121
    let path = try tempConfigPath()
    try ConfigFile.save(storeSample, to: path)
    var reloads = 0
    let store = ConfigStore(path: path, reload: { reloads += 1 })
    store.load()

    store.change("Rename Preset") { config in
        config.n4?.presets[0].name = "Office"
        config.n4?.activePreset = "Office"
    }
    store.change("Delete Preset") { config in
        config.n4?.presets.remove(at: 0)
        config.n4?.activePreset = "Music"
    }
    #expect(store.undoName == "Delete Preset")
    store.undo()
    #expect(store.config.n4?.presets.map(\.name) == ["Office", "Music"])
    store.undo()
    #expect(store.config == storeSample)
    #expect(try ConfigFile.load(at: path).get() == storeSample)
    #expect(reloads == 4)
    #expect(!store.canUndo)

    store.redo()
    #expect(store.config.n4?.activePreset == "Office")
    // A new change after an undo drops what could be redone.
    store.change("Change Brightness") { $0.n4?.brightness = 10 }
    #expect(!store.canRedo)
}

@MainActor @Test func handEditIsPickedUp() throws {   // T-122
    let path = try tempConfigPath()
    try ConfigFile.save(storeSample, to: path)
    let store = ConfigStore(path: path, reload: {})
    store.load()

    // Edited by hand while the app is open: the next change builds on the hand edit instead of dropping it.
    var edited = storeSample
    edited.n4?.brightness = 12
    try ConfigFile.save(edited, to: path)
    store.change("Change Action") { $0.n4?.presets[0].keys["key_2"] = ButtonConfig(action: "media_play_pause") }
    let saved = try ConfigFile.load(at: path).get()
    #expect(saved.n4?.brightness == 12)
    #expect(saved.n4?.keys["key_2"]?.action == "media_play_pause")

    // A hand edit that doesn't load: the store says so and never saves over the broken file.
    try Data("{ broken".utf8).write(to: URL(fileURLWithPath: path))
    store.change("Change Brightness") { $0.n4?.brightness = 99 }
    #expect(store.problem != nil)
    #expect(try String(contentsOfFile: path, encoding: .utf8) == "{ broken")
    #expect(store.config.n4?.brightness == 12)

    // Fixed by hand: changes work again.
    try ConfigFile.save(edited, to: path)
    store.change("Change Brightness") { $0.n4?.brightness = 99 }
    #expect(store.problem == nil)
    #expect(try ConfigFile.load(at: path).get().n4?.brightness == 99)
}

@MainActor @Test func aFixedProblemUnblocksEdits() throws {   // T-122 (review I1)
    let path = try tempConfigPath()
    let folder = (path as NSString).deletingLastPathComponent
    try ConfigFile.save(storeSample, to: path)
    let store = ConfigStore(path: path, reload: {})
    store.load()

    // A hand edit saved group-writable is refused; fixed as the message says (chmod 600) the bytes don't change,
    // and edits work again anyway.
    var edited = storeSample
    edited.n4?.brightness = 15
    try edited.encoded().write(to: URL(fileURLWithPath: path))
    chmod(path, 0o664)
    store.change("Change Brightness") { $0.n4?.brightness = 10 }
    #expect(store.problem?.contains("chmod 600") == true)
    chmod(path, 0o600)
    store.change("Change Brightness") { $0.n4?.brightness = 20 }
    #expect(store.problem == nil)
    #expect(try ConfigFile.load(at: path).get().n4?.brightness == 20)

    // A save that fails (folder not writable) is shown, and doesn't block the next try once it can work.
    chmod(folder, 0o500)
    store.change("Change Brightness") { $0.n4?.brightness = 30 }
    #expect(store.problem != nil)
    chmod(folder, 0o700)
    store.change("Change Brightness") { $0.n4?.brightness = 40 }
    #expect(store.problem == nil)
    #expect(try ConfigFile.load(at: path).get().n4?.brightness == 40)
}

@MainActor @Test func undoKeepsAHandEdit() throws {   // T-121 (review I2)
    let path = try tempConfigPath()
    try ConfigFile.save(storeSample, to: path)
    let store = ConfigStore(path: path, reload: {})
    store.load()
    store.change("Change Action") { $0.setButton(.n4, "key_2", ButtonConfig(action: "media_next")) }

    // Edited by hand afterwards: undo can't put back a config from before it without losing it, so the app's
    // history starts again from the hand edit, and says so.
    var edited = try ConfigFile.load(at: path).get()
    edited.setButton(.n4, "key_9", ButtonConfig(action: "media_previous"))
    try ConfigFile.save(edited, to: path)
    store.undo()
    let now = try ConfigFile.load(at: path).get()
    #expect(now.button(.n4, "key_9")?.action == "media_previous")
    #expect(now.button(.n4, "key_2")?.action == "media_next")
    #expect(!store.canUndo)
    #expect(store.notice == "Picked up a change made outside DeckOut; undo starts again from here")
}
