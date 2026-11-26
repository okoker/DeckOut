import CoreGraphics
import DeckCore
import Foundation
import Testing
@testable import DeckOutKit

@Test func screenFollowsTheDecks() {   // T-118
    let none: Set<DeckKind> = [], both: Set<DeckKind> = [.n3, .n4]
    // Nothing shown yet (launch, or "Plug in your deck"): none → plug in, one → open it, both → pick.
    #expect(AppModel.deckScreen(shown: nil, connected: none) == .plugIn)
    #expect(AppModel.deckScreen(shown: nil, connected: [.n4]) == .deck(.n4))
    #expect(AppModel.deckScreen(shown: nil, connected: [.n3]) == .deck(.n3))
    #expect(AppModel.deckScreen(shown: nil, connected: both) == .pickDeck)
    // A deck on screen stays while it's plugged in, also when the other one arrives.
    #expect(AppModel.deckScreen(shown: .n4, connected: [.n4]) == .deck(.n4))
    #expect(AppModel.deckScreen(shown: .n4, connected: both) == .deck(.n4))
    // The deck on screen is unplugged: the other one, else plug in. Never a deck that isn't there.
    #expect(AppModel.deckScreen(shown: .n4, connected: [.n3]) == .deck(.n3))
    #expect(AppModel.deckScreen(shown: .n3, connected: none) == .plugIn)
}

@Test func screenBeforeTheDecks() {   // T-118
    let ok = AgentStatus(version: "2", build: "b", decks: ["n4"], activePresets: [:], configProblem: nil,
                         environment: EnvironmentStatus(state: .resolved, detail: nil))
    func screen(location: String? = nil, registration: RegistrationState? = .enabled,
                link: AgentLink.State = .connected, status: AgentStatus? = ok) -> Screen {
        AppModel.screen(locationProblem: location, registration: registration, linkState: link, status: status, shown: nil)
    }
    #expect(screen(location: "Move it") == .moveToApplications("Move it"))
    #expect(screen(registration: nil) == .starting)
    #expect(screen(registration: .needsApproval) == .needsApproval)
    #expect(screen(registration: .failed("boom")) == .agentProblem("boom"))
    #expect(screen(link: .notAnswering) == .agentProblem(AppModel.notAnsweringText))
    #expect(screen(link: .connecting, status: nil) == .starting)
    #expect(screen() == .deck(.n4))
    // Another build still running after one restart: the decks still show; the status line says so.
    #expect(screen(link: .versionMismatch(agent: "a", app: "b")) == .deck(.n4))
}

// MARK: - Knob lists in the window (docs/design/knob_lists.md)

/// Text tiles at the strip block's size, written to a temp folder: stand-in icons for list items.
@MainActor func stripTiles(_ names: [String]) throws -> [String] {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deckout-tiles-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return try names.enumerated().map { index, name in
        let tile = IconTile(kind: .text, text: name, symbol: nil, style: nil,
                            background: IconRow.swatches[index % IconRow.swatches.count], foreground: nil)
        let png = try #require(TileRenderer.render(tile, library: nil, width: TileRenderer.stripWidth,
                                                   height: TileRenderer.stripHeight))
        let path = folder.appendingPathComponent("\(name).png").path
        try png.write(to: URL(fileURLWithPath: path))
        return path
    }
}

private func pixels(_ image: CGImage?) -> Data? { image?.dataProvider?.data as Data? }

@MainActor @Test func editorIdentityFollowsThePreset() throws {   // T-214
    // BL-035: a swipe that makes another preset live rebuilds the editor, so text half-typed for one preset never
    // lands in the next.
    let config = AppConfig(n4: N4Section(brightness: 75, swipe: .nextPreset, lockPhoto: nil,
                                         presets: [N4Preset(name: "Work", keys: [:], strip: [:]),
                                                   N4Preset(name: "Music", keys: [:], strip: [:])],
                                         activePreset: "Work"))
    let model = try previewModel(config, deck: .n4, selection: "knob_1")
    let before = model.editorIdentity
    model.store?.change("Swipe") { $0.makeLive("Music", deck: .n4) }
    #expect(model.selection == "knob_1")
    #expect(model.editorIdentity != before)
}

@MainActor @Test func listBlockShowsThePickInTheWindow() throws {   // T-215
    let icons = try stripTiles(["Wikipedia", "GitHub", "BBC"])
    let list = KnobConfig(list: icons.map { ButtonConfig(action: "url:https://example.com", icon: $0) })
    let config = AppConfig(n4: N4Section(brightness: 75, swipe: nil, lockPhoto: nil,
                                         presets: [N4Preset(name: "Work", keys: [:],
                                                            strip: ["1": StripBlockConfig(type: .volume)],
                                                            knobs: ["knob_1": list])],
                                         activePreset: "Work"))
    let model = try previewModel(config, deck: .n4, selection: nil)
    let expected = icons.map { pixels(DeckPreview.stripPicture(path: $0)) }
    #expect(pixels(model.images["1"]) == expected[0])                  // before the agent says: the first item
    model.livePicks = ["knob_1": 2]
    #expect(pixels(model.images["1"]) == expected[2])
    model.livePicks = ["knob_1": 7]                                      // a pick the list no longer reaches
    #expect(pixels(model.images["1"]) == expected[0])
}
