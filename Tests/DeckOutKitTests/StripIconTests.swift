import AppKit
import DeckCore
import Testing
@testable import DeckOutKit

// A strip block takes a key's icons: a text or symbol tile drawn at the strip's shape, an image, or none. Setting
// its tap never changes what it shows (the owner: a block stays blank until its icon is picked).
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
