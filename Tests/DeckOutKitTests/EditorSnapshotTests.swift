import DeckCore
import SwiftUI
import Testing
@testable import DeckOutKit

/// A model over a config in a temp file, with no agent: what the editors see.
@MainActor func previewModel(_ config: AppConfig, deck: DeckKind, selection: String?) throws -> AppModel {
    let path = try tempConfigPath()
    try ConfigFile.save(config, to: path)
    let store = ConfigStore(path: path, reload: {})
    store.load()
    let model = AppModel(identity: nil, appBuild: "test", link: nil, store: store, registrar: nil)
    model.shown = deck
    model.selection = selection
    model.rebuildStaticImages()
    return model
}

// The window with the editor for each kind of action, drawn in a real (offscreen) window: PNGs for a look.
@MainActor @Test func editorsDraw() throws {   // T-129 (design check)
    let notes = "/System/Applications/Notes.app"
    let kinds: [(String, ButtonConfig)] = [
        ("app", ButtonConfig(action: "app:\(notes)", icon: "\(notes)/Contents/Resources/AppIcon.icns")),
        ("url", ButtonConfig(action: "url:https://example.com/status")),
        ("shortcut", ButtonConfig(action: "key:cmd+shift+4")),
        ("volume", ButtonConfig(action: "system_volume", step: -5)),
        ("command", ButtonConfig(action: "shell:open -a 'Google Chrome'")),
        ("zr7", ButtonConfig(action: "zr7_mute_toggle")),
        ("bad-url", ButtonConfig(action: "url:example")),
    ]
    for (name, button) in kinds {
        var config = AppConfig.empty
        config.setButton(.n4, "key_3", button)
        let model = try previewModel(config, deck: .n4, selection: "key_3")
        #expect(model.config?.button(.n4, "key_3") == button)
        for dark in [false, true] {
            let png = try Snapshot.windowPNG(DeckStage(model: model, face: DeckFace.of(.n4)), size: MainWindow.size, dark: dark)
            #expect(png.count > 1000)
            try png.write(to: snapshotFolder.appendingPathComponent("editor-\(name)-\(dark ? "dark" : "light").png"))
        }
    }
}

@MainActor @Test func knobAndStripEditorsDraw() throws {   // T-129 (design check)
    var config = AppConfig.empty
    config.setKnob(.n4, "knob_4", KnobConfig(rotate: KnobAction(action: "system_volume", step: 2),
                                             press: KnobAction(action: "system_mute_toggle")))
    config.setStripBlock("1", StripBlockConfig(type: .internet, action: "url:https://example.com"))
    config.setButton(.n4, "key_2", ButtonConfig(action: "script:/nonexistent/backup.sh"))
    for (name, selection) in [("knob", "knob_4"), ("strip", "1"), ("missing", "key_2")] {
        let model = try previewModel(config, deck: .n4, selection: selection)
        for dark in [false, true] {
            let png = try Snapshot.windowPNG(DeckStage(model: model, face: DeckFace.of(.n4)), size: MainWindow.size, dark: dark)
            try png.write(to: snapshotFolder.appendingPathComponent("editor-\(name)-\(dark ? "dark" : "light").png"))
        }
    }
    let model = try previewModel(config, deck: .n4, selection: nil)
    #expect(model.problems == ["key_2": "The script isn't there any more"])
}

@MainActor @Test func accessibilityNoteDraws() throws {   // T-129 (design check)
    let note = AccessibilityNote {}.frame(width: 264).padding(18)
    try Snapshot.windowPNG(note, size: CGSize(width: 300, height: 140), dark: false)
        .write(to: snapshotFolder.appendingPathComponent("accessibility-light.png"))
}

@MainActor @Test func anEditKeepsAHandEditedIcon() throws {   // T-122 (review M2)
    var config = AppConfig.empty
    config.setButton(.n4, "key_1", ButtonConfig(action: "media_next", icon: "/a/icons/image-1.png"))
    let model = try previewModel(config, deck: .n4, selection: "key_1")
    let path = try #require(model.store?.path)
    var edited = config
    edited.setButton(.n4, "key_1", ButtonConfig(action: "media_next", icon: "/b/icons/image-2.png"))
    try ConfigFile.save(edited, to: path)
    model.setAction(.playPause, button: "key_1", on: .n4)
    #expect(try ConfigFile.load(at: path).get().button(.n4, "key_1") == ButtonConfig(action: "media_play_pause", icon: "/b/icons/image-2.png"))
}

@MainActor @Test func brightnessDoesNotRedrawKeys() throws {   // T-120 (review M7)
    var config = AppConfig.empty
    config.setButton(.n4, "key_1", ButtonConfig(action: "media_next", icon: "/System/Applications/Notes.app/Contents/Resources/AppIcon.icns"))
    let model = try previewModel(config, deck: .n4, selection: nil)
    let builds = model.staticImageBuilds
    for value in [70, 60, 50] { model.setBrightness(value) }
    #expect(model.staticImageBuilds == builds)        // a slider drag doesn't re-decode every icon
    model.setAction(.playPause, button: "key_2", on: .n4)
    #expect(model.staticImageBuilds == builds)        // nor does an action without an icon change
    model.setIcon(nil, button: "key_1", on: .n4)
    #expect(model.staticImageBuilds == builds + 1)    // an icon change does
}
