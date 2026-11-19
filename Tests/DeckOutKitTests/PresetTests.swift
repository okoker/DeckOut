import DeckCore
import Foundation
import Testing
@testable import DeckOutKit

private let twoPresets = AppConfig(n4: N4Section(
    brightness: 75, knobs: [:], swipe: nil, lockPhoto: nil,
    presets: [N4Preset(name: "Work", keys: ["key_1": ButtonConfig(action: "media_next")], strip: [:]),
              N4Preset(name: "Music", keys: [:], strip: [:])],
    activePreset: "Work"))

@Test func presetOperations() {   // T-132
    var config = twoPresets
    #expect(config.presetNames(.n4) == ["Work", "Music"])
    #expect(config.livePreset(.n4) == "Work")

    config.makeLive("Music", deck: .n4)
    #expect(config.livePreset(.n4) == "Music")

    // New: a blank layout under the first free name, and live.
    let made = config.newPreset(deck: .n4)
    #expect(made == "Preset 3")
    #expect(config.livePreset(.n4) == "Preset 3")
    #expect(config.n4?.presets.last?.keys.isEmpty == true)

    // Duplicate: a copy of the layout, live.
    config.makeLive("Work", deck: .n4)
    let copy1 = config.duplicatePreset("Work", deck: .n4)
    let copy2 = config.duplicatePreset("Work", deck: .n4)
    #expect(copy1 == "Work copy")
    #expect(copy2 == "Work copy 2")
    #expect(config.n4?.presets.first { $0.name == "Work copy" }?.keys["key_1"]?.action == "media_next")

    // Rename: never empty, never a name already taken; the live one stays live.
    let blank = config.renamePreset("Work copy 2", to: "  ", deck: .n4)
    let taken = config.renamePreset("Work copy 2", to: "Music", deck: .n4)
    let renamed = config.renamePreset("Work copy 2", to: "Evening", deck: .n4)
    #expect(!blank && !taken && renamed)
    #expect(config.livePreset(.n4) == "Evening")

    // The N3 the same way; a deck with no section yet gets one.
    var empty = AppConfig.empty
    let n3Made = empty.newPreset(deck: .n3)
    #expect(n3Made == "Preset 2")
    #expect(empty.presetNames(.n3) == ["Default", "Preset 2"])

    // Brightness, per deck, 0–100.
    config.setBrightness(.n4, 140)
    #expect(config.brightness(.n4) == 100)
    config.setBrightness(.n4, 40)
    #expect(config.brightness(.n4) == 40)
}

@MainActor @Test func deleteLiveFallsBackAndUndoes() throws {   // T-133
    var config = twoPresets
    // Never the last one.
    var single = AppConfig.empty
    _ = single.newPreset(deck: .n4)
    _ = single.deletePreset("Default", deck: .n4)
    let lastDeleted = single.deletePreset("Preset 2", deck: .n4)
    #expect(!lastDeleted)
    #expect(single.presetNames(.n4) == ["Preset 2"])

    // Deleting the live one makes the first left live.
    let deleted = config.deletePreset("Work", deck: .n4)
    #expect(deleted)
    #expect(config.livePreset(.n4) == "Music")

    // Through the store: delete, then undo brings it back, live again.
    let path = try tempConfigPath()
    try ConfigFile.save(twoPresets, to: path)
    let store = ConfigStore(path: path, reload: {})
    store.load()
    store.change("Delete Preset") { _ = $0.deletePreset("Work", deck: .n4) }
    #expect(store.config.livePreset(.n4) == "Music")
    store.undo()
    #expect(store.config == twoPresets)
    #expect(try ConfigFile.load(at: path).get() == twoPresets)
}

@MainActor @Test func sliderDragIsOneUndo() throws {   // T-120
    let path = try tempConfigPath()
    try ConfigFile.save(twoPresets, to: path)
    let store = ConfigStore(path: path, reload: {})
    store.load()
    for value in stride(from: 70, through: 30, by: -5) {
        store.change("Change Brightness", coalescing: true) { $0.setBrightness(.n4, value) }
    }
    #expect(store.config.brightness(.n4) == 30)
    store.undo()
    #expect(store.config.brightness(.n4) == 75)    // one undo for the whole drag
    #expect(!store.canUndo)
}
