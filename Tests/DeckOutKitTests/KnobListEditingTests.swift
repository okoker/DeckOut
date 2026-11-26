import DeckCore
import Foundation
import Testing
@testable import DeckOutKit

// Editing knob lists in the app (docs/design/knob_lists.md): each edit is one undo step, saved whole.

private let volumeKnob = KnobConfig(rotate: KnobAction(action: "system_volume", step: 5),
                                    press: KnobAction(action: "system_mute_toggle"))
private let wikipedia = "https://en.wikipedia.org", github = "https://github.com", bbc = "https://www.bbc.co.uk"

private func n4(knobs: [String: KnobConfig] = [:], strip: [String: StripBlockConfig] = [:]) -> AppConfig {
    AppConfig(n4: N4Section(brightness: 75, swipe: nil, lockPhoto: nil,
                            presets: [N4Preset(name: "Work", keys: [:], strip: strip, knobs: knobs)],
                            activePreset: "Work"))
}

@MainActor private func actions(_ model: AppModel) -> [String]? {
    model.config?.knob(.n4, "knob_1")?.list?.map(\.action)
}

@MainActor @Test func makeListClearsTheBlockAboveInOneUndo() throws {   // T-208
    let start = n4(knobs: ["knob_1": volumeKnob], strip: ["1": StripBlockConfig(type: .internet)])
    let model = try previewModel(start, deck: .n4, selection: "knob_1")
    model.makeKnobList("knob_1")
    #expect(model.config?.knob(.n4, "knob_1")?.list == [])
    #expect(model.config?.stripBlock("1") == nil)
    #expect(model.store?.undoName == "Make List")
    model.store?.undo()
    #expect(model.config == start)
}

@MainActor @Test func listEditsAreOneUndoEach() throws {               // T-209
    let model = try previewModel(n4(), deck: .n4, selection: "knob_1")
    model.makeKnobList("knob_1")
    var at = model.addListItem(knob: "knob_1", after: nil)
    model.setListItemAction(.openWebsite(wikipedia), knob: "knob_1", at: at)
    at = model.addListItem(knob: "knob_1", after: at)
    model.setListItemAction(.openWebsite(github), knob: "knob_1", at: at)
    at = model.addListItem(knob: "knob_1", after: at)
    #expect(at == 2)
    model.setListItemAction(.openWebsite(bbc), knob: "knob_1", at: at)
    model.moveListItem(knob: "knob_1", from: 2, to: 0)
    model.removeListItem(knob: "knob_1", at: 1)
    #expect(actions(model) == ["url:" + bbc, "url:" + github])
    #expect(model.captions["knob_1"] == "List of 2")
    // A new item goes after the one given.
    let between = model.addListItem(knob: "knob_1", after: 0)
    #expect(between == 1 && actions(model) == ["url:" + bbc, "none", "url:" + github])
    model.store?.undo()
    // Each edit undoes on its own: the remove, the move, the action, the add.
    model.store?.undo()
    #expect(actions(model) == ["url:" + bbc, "url:" + wikipedia, "url:" + github])
    model.store?.undo()
    #expect(actions(model) == ["url:" + wikipedia, "url:" + github, "url:" + bbc])
    model.store?.undo()
    #expect(actions(model) == ["url:" + wikipedia, "url:" + github, "none"])
    model.store?.undo()
    #expect(actions(model) == ["url:" + wikipedia, "url:" + github])
}

@MainActor @Test func listItemAppIconFollowsTheApp() throws {         // T-210
    let model = try previewModel(n4(knobs: ["knob_1": KnobConfig(list: [ButtonConfig(action: "none")])]),
                                 deck: .n4, selection: "knob_1")
    model.setListItemAction(.openApp("/System/Applications/Notes.app"), knob: "knob_1", at: 0)
    let icon = try #require(model.config?.knob(.n4, "knob_1")?.list?.first?.icon)
    #expect(icon.contains("/icons/app-") && FileManager.default.fileExists(atPath: icon))
    // An image the person chose stays when the action changes.
    model.setListItemIcon("/tmp/mine.png", knob: "knob_1", at: 0)
    model.setListItemAction(.openApp("/System/Applications/Calendar.app"), knob: "knob_1", at: 0)
    #expect(model.config?.knob(.n4, "knob_1")?.list?.first?.icon == "/tmp/mine.png")
}

@MainActor @Test func listKnobSurvivesAppSave() throws {               // T-212
    // The app saves the whole config on every edit: an unrelated edit must keep the list, items, icons and tiles.
    let tile = IconTile(kind: .text, text: "GitHub", symbol: nil, style: nil, background: "#5E5CE6", foreground: nil)
    let list = KnobConfig(list: [ButtonConfig(action: "url:" + github, icon: "/tmp/github.png", tile: tile),
                                 ButtonConfig(action: "app:/Applications/Safari.app")])
    let model = try previewModel(n4(knobs: ["knob_1": list, "knob_4": volumeKnob]), deck: .n4, selection: nil)
    model.setBrightness(30)
    let path = try #require(model.store?.path)
    let saved = try ConfigFile.load(at: path).get()
    #expect(saved.n4?.brightness == 30)
    #expect(saved.n4?.knobs["knob_1"] == list)
}

@MainActor @Test func missingListIconMarksTheKnob() throws {           // T-213
    let list = KnobConfig(list: [ButtonConfig(action: "url:" + github, icon: "/nonexistent/github.png")])
    let model = try previewModel(n4(knobs: ["knob_1": list]), deck: .n4, selection: nil)
    #expect(model.problems["knob_1"] == "Item 1: the icon file isn't there any more")
    let app = KnobConfig(list: [ButtonConfig(action: "url:" + github),
                                ButtonConfig(action: "app:/Applications/Gone.app")])
    let other = try previewModel(n4(knobs: ["knob_1": app]), deck: .n4, selection: nil)
    #expect(other.problems["knob_1"] == "Item 2: the app isn't there any more")
}

@Test func listItemEditorIsRebuiltAfterARemove() {                    // T-219
    // Removing an item can leave the selection on the same number: the item editor must still be built afresh, so
    // text half-typed for the removed item never lands on the one that moved up.
    #expect(KnobListEditor.itemIdentity(index: 2, count: 5) != KnobListEditor.itemIdentity(index: 2, count: 4))
    #expect(KnobListEditor.itemIdentity(index: 2, count: 5) != KnobListEditor.itemIdentity(index: 3, count: 5))
}
