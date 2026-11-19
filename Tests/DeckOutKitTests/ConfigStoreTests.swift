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
