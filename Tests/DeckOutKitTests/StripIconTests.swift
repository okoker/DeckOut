import AppKit
import DeckCore
import Testing
@testable import DeckOutKit

// A strip block takes a key's icons: a text or symbol tile drawn at the strip's shape, an image, or none. Setting
// its tap never puts an icon on it (the owner: a block stays blank until its icon is picked).
@MainActor @Test func stripIconEdits() throws {   // T-157
    let notes = "/System/Applications/Notes.app"
    var config = AppConfig.empty
    config.setStripBlock("1", StripBlockConfig(type: .internet, action: "url:https://example.com"))
    let model = try previewModel(config, deck: .n4, selection: "3")
    let store = try #require(model.store)

    // A text tile on a block with only a tap: it shows the icon now, 352 × 224; the tap and how it was made are kept.
    let tile = IconTile(kind: .text, text: "Weather", symbol: nil, style: nil, background: "#0A84FF", foreground: nil)
    model.setStripTap(.runCommand("echo hi"), block: "3")
    model.setStripTile(tile, block: "3")
    let block = try #require(model.stripBlock("3"))
    #expect(block.type == .picture && block.tile == tile && block.action == "shell:echo hi")
    let icon = try #require(block.icon)
    let rep = try #require(NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: icon))))
    #expect(rep.pixelsWide == 352 && rep.pixelsHigh == 224)
    store.undo()                                                    // one step
    #expect(model.stripBlock("3")?.type == .empty && model.stripBlock("3")?.action == "shell:echo hi")
    store.redo()

    // A live reading drops the icon and keeps the tap.
    model.setStripType(.load, block: "3")
    #expect(model.stripBlock("3") == StripBlockConfig(type: .load, action: "shell:echo hi"))

    // A tap never puts an icon on a block: an empty one stays blank, a reading stays.
    model.setStripTap(.openApp(notes), block: "4")
    #expect(model.stripBlock("4")?.type == .empty && model.stripBlock("4")?.icon == nil)
    model.setStripTap(.openApp(notes), block: "1")
    #expect(model.stripBlock("1")?.type == .internet && model.stripBlock("1")?.icon == nil)

    // No Icon: still an icon block, with nothing on it and no tile.
    model.setStripTile(tile, block: "2")
    model.setStripIcon(nil, block: "2")
    #expect(model.stripBlock("2") == StripBlockConfig(type: .picture))
    // An image chosen for a block replaces its tile.
    model.setStripTile(tile, block: "2")
    model.setStripIcon("/icons/image-1.png", block: "2")
    #expect(model.stripBlock("2") == StripBlockConfig(type: .picture, icon: "/icons/image-1.png"))
}

// A block showing its tap's app's own icon follows the tap to another app, as a key does (BL-030); the person's own
// image, a text tile or no icon stays.
@MainActor @Test func stripAppIconFollowsTheTap() throws {   // T-165
    let notes = "/System/Applications/Notes.app"
    let calculator = "/System/Applications/Calculator.app"
    let model = try previewModel(AppConfig.empty, deck: .n4, selection: "1")
    let store = try #require(model.store)
    let notesIcon = try #require(model.appIcon(for: notes))
    let calculatorIcon = try #require(IconFiles.appIcon(appPath: calculator, folder: IconFiles.folder(forConfig: store.path)))

    // Notes' icon on a block that opens Notes: the tap goes to Calculator, so does the icon, in one undo step.
    model.setStripTap(.openApp(notes), block: "1")
    model.setStripIcon(notesIcon, block: "1")
    model.setStripTap(.openApp(calculator), block: "1")
    #expect(model.stripBlock("1") == StripBlockConfig(type: .picture, action: "app:" + calculator, icon: calculatorIcon))
    store.undo()
    #expect(model.stripBlock("1") == StripBlockConfig(type: .picture, action: "app:" + notes, icon: notesIcon))
    // A tap that isn't Open App keeps the icon.
    model.setStripTap(.runCommand("echo hi"), block: "1")
    #expect(model.stripBlock("1") == StripBlockConfig(type: .picture, action: "shell:echo hi", icon: notesIcon))

    // A chosen image stays.
    let source = FileManager.default.temporaryDirectory.appendingPathComponent("deckout-src-\(UUID().uuidString).png").path
    let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    try #require(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: source))
    let image = try #require(model.importImage(source))
    model.setStripTap(.openApp(notes), block: "2")
    model.setStripIcon(image, block: "2")
    model.setStripTap(.openApp(calculator), block: "2")
    #expect(model.stripBlock("2") == StripBlockConfig(type: .picture, action: "app:" + calculator, icon: image))

    // A text tile stays.
    let tile = IconTile(kind: .text, text: "Notes", symbol: nil, style: nil, background: "#0A84FF", foreground: nil)
    model.setStripTap(.openApp(notes), block: "3")
    model.setStripTile(tile, block: "3")
    let drawn = try #require(model.stripBlock("3")?.icon)
    model.setStripTap(.openApp(calculator), block: "3")
    #expect(model.stripBlock("3") == StripBlockConfig(type: .picture, action: "app:" + calculator, icon: drawn, tile: tile))

    // An icon block with no icon gets none.
    model.setStripIcon(nil, block: "4")
    model.setStripTap(.openApp(calculator), block: "4")
    #expect(model.stripBlock("4") == StripBlockConfig(type: .picture, action: "app:" + calculator))
}

// An emptied Host field saves the default host its placeholder shows, not an empty one the agent can't ping (BL-013);
// a typed host is saved trimmed.
@MainActor @Test func emptiedHostSavesTheDefault() throws {   // T-166
    var config = AppConfig.empty
    config.setStripBlock("1", StripBlockConfig(type: .internet, host: "example.net"))
    let model = try previewModel(config, deck: .n4, selection: "1")
    for typed in ["", "   ", " \n"] {
        model.setStripHost("example.net", block: "1")
        model.setStripHost(typed, block: "1")
        #expect(model.stripBlock("1")?.host == StripBlockConfig.defaultHost, "\(typed.debugDescription)")
    }
    model.setStripHost(" example.org\n", block: "1")
    #expect(model.stripBlock("1")?.host == "example.org")
}
