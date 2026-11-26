import DeckCore
import Foundation
import Testing
@testable import DeckOutKit

private let twoPresets = AppConfig(n4: N4Section(
    brightness: 75, swipe: nil, lockPhoto: nil,
    presets: [N4Preset(name: "Work", keys: ["key_1": ButtonConfig(action: "media_next")], strip: [:]),
              N4Preset(name: "Music", keys: [:], strip: [:])],
    activePreset: "Work"))

@Test func presetOperations() {   // T-132
    var config = twoPresets
    #expect(config.presetNames(.n4) == ["Work", "Music"])
    #expect(config.livePreset(.n4) == "Work")

    config.makeLive("Music", deck: .n4)
    #expect(config.livePreset(.n4) == "Music")

    // New: a blank layout under the name given (the sheet offers the first free "Preset N"), and live.
    #expect(config.suggestedPresetName(.n4) == "Preset 3")
    let made = config.addPreset("Preset 3", deck: .n4)
    #expect(made)
    #expect(config.livePreset(.n4) == "Preset 3")
    #expect(config.n4?.presets.last?.keys.isEmpty == true)
    // An empty name or one already taken: false, and nothing changes.
    let before = config
    let blankName = config.addPreset("  ", deck: .n4)
    let takenName = config.addPreset(" Music ", deck: .n4)
    #expect(!blankName && !takenName)
    #expect(config == before)

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
    #expect(empty.suggestedPresetName(.n3) == "Preset 2")
    let refused = empty.addPreset(" ", deck: .n3)
    #expect(!refused && empty == AppConfig.empty)        // not even a section added
    let n3Made = empty.addPreset("Preset 2", deck: .n3)
    #expect(n3Made)
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
    _ = single.addPreset("Preset 2", deck: .n4)
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

// The pull-down (owner, 20/11/2026): the live preset first, then Default (the first in the file) when another is
// live; the other presets below the actions.
@Test func presetMenuOrder() {   // T-159
    let presets = ["Default", "Work", "Music"]
    let home = PresetMenuLayout.items(presets: presets, live: "Default")
    #expect(home.top == ["Default"] && home.rest == ["Work", "Music"])
    let work = PresetMenuLayout.items(presets: presets, live: "Work")
    #expect(work.top == ["Work", "Default"] && work.rest == ["Music"])
    let renamed = PresetMenuLayout.items(presets: ["Home", "Work"], live: "Work")    // a renamed Default keeps its place
    #expect(renamed.top == ["Work", "Home"] && renamed.rest.isEmpty)
}

@Test func presetNameProblems() {   // T-159
    let taken = ["Default", "Work"]
    #expect(PresetNameSheet.problem("  ", taken: taken, current: nil) == "Type a name.")
    #expect(PresetNameSheet.problem(" Work ", taken: taken, current: nil) == "There's already a preset called “Work”.")
    #expect(PresetNameSheet.problem("Work", taken: taken, current: "Work") == nil)      // renaming to its own name
    #expect(PresetNameSheet.problem("Evening", taken: taken, current: nil) == nil)
}

// New Preset is one undo step; a refused name (the sheet would say why) changes nothing and leaves no step. Cancel
// never reaches the model.
@MainActor @Test func newPresetUndoesInOne() throws {   // T-159
    let model = try previewModel(twoPresets, deck: .n4, selection: nil)
    let store = try #require(model.store)
    let added = model.newPreset(named: "Evening")
    #expect(added && model.livePreset == "Evening" && model.presetNames == ["Work", "Music", "Evening"])
    store.undo()
    #expect(model.livePreset == "Work" && model.presetNames == ["Work", "Music"])
    #expect(!store.canUndo)
    let taken = model.newPreset(named: "Music")
    #expect(!taken && !store.canUndo && store.config == twoPresets)
}

// Rename renames the preset the sheet was opened for, even if another became live meanwhile (BL-011).
@MainActor @Test func renameNamesThePresetItWasOpenedFor() throws {   // T-159
    let model = try previewModel(twoPresets, deck: .n4, selection: nil)
    model.makeLive("Music")
    let renamed = model.renamePreset("Work", to: "Day")
    #expect(renamed && model.presetNames == ["Day", "Music"] && model.livePreset == "Music")
}

@MainActor @Test func presetSheetsDraw() throws {   // T-159 (design check)
    let sheets = [
        ("new", PresetNameSheet(title: "New Preset", action: "Create", name: "Preset 3", current: nil,
                                taken: ["Default", "Work"]) { _ in true }),
        ("rename-taken", PresetNameSheet(title: "Rename Preset", action: "Rename", name: "Default", current: "Work",
                                         taken: ["Default", "Work"]) { _ in true }),
    ]
    for (name, sheet) in sheets {
        for dark in [false, true] {
            try Snapshot.windowPNG(sheet, size: PresetNameSheet.size, dark: dark)
                .write(to: snapshotFolder.appendingPathComponent("preset-sheet-\(name)-\(dark ? "dark" : "light").png"))
        }
    }
}

@Test func aNewN4SwipesThroughPresets() {   // T-192
    // A new N4 section made by the app swipes through its presets (BL-033); a section that already exists is never
    // given the swipe behind the person's back.
    var fresh = AppConfig.empty
    fresh.setBrightness(.n4, 50)
    #expect(fresh.n4?.swipe == ActionConfig.nextPreset)
    var existing = twoPresets
    existing.setBrightness(.n4, 40)
    #expect(existing.n4?.swipe == nil)
}

@Test func newPresetCopiesBuiltInKnobsOnly() {   // T-211
    // New Preset starts blank but for the knobs' built-in halves (volume, mute, monitor brightness, switch monitor);
    // Duplicate copies everything, lists included (owner, 26/11/2026).
    let volume = KnobAction(action: "system_volume", step: 5)
    let workKnobs = [
        "knob_1": KnobConfig(list: [ButtonConfig(action: "url:https://github.com")]),
        "knob_2": KnobConfig(rotate: volume, press: KnobAction(action: "app:/Applications/Safari.app")),
        "knob_4": KnobConfig(rotate: volume, press: KnobAction(action: "system_mute_toggle")),
    ]
    var config = AppConfig(
        n3: N3Section(brightness: 75, presets: [N3Preset(name: "A", buttons: [:], knobs: [
            "big": KnobConfig(rotate: KnobAction(action: "display_brightness", step: 5),
                              press: KnobAction(action: "shell:open -a Notes")),
            "small_1": KnobConfig(rotate: KnobAction(action: "none"), press: KnobAction(action: "media_next")),
        ])], activePreset: "A"),
        n4: N4Section(brightness: 75, swipe: nil, lockPhoto: nil,
                      presets: [N4Preset(name: "Work", keys: ["key_1": ButtonConfig(action: "media_next")], strip: [:],
                                         knobs: workKnobs)],
                      activePreset: "Work"))
    _ = config.addPreset("Music", deck: .n4)
    #expect(config.livePreset(.n4) == "Music")
    #expect(config.n4?.keys.isEmpty == true)
    #expect(config.n4?.knobs == ["knob_2": KnobConfig(rotate: volume, press: KnobAction(action: "none")),
                                 "knob_4": workKnobs["knob_4"]!])
    _ = config.addPreset("B", deck: .n3)
    #expect(config.n3?.knobs == ["big": KnobConfig(rotate: KnobAction(action: "display_brightness", step: 5),
                                                   press: KnobAction(action: "none"))])
    let copy = config.duplicatePreset("Work", deck: .n4)
    #expect(config.n4?.presets.first { $0.name == copy }?.knobs == workKnobs)
}
