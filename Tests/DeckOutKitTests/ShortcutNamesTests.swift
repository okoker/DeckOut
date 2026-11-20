import DeckCore
import Foundation
import Testing
@testable import DeckOutKit

// The Shortcut picker's list, read from a stand-in for `/usr/bin/shortcuts` (never the person's own Shortcuts).

@MainActor @Test func aShortcutMadeMeanwhileIsOffered() async throws {   // T-175
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deckout-shortcuts-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let tool = folder.appendingPathComponent("shortcuts").path
    func offer(_ names: [String]) throws {
        let script = "#!/bin/sh\n" + names.map { "echo '\($0)'\n" }.joined()
        try script.write(toFile: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool)
    }
    let model = try previewModel(.empty, deck: .n4, selection: nil)
    model.shortcutsTool = tool

    // A picker appears: the list is read.
    try offer(["Morning"])
    model.loadShortcutNames()
    #expect(await until { model.shortcutNames == ["Morning"] })

    // The person makes a Shortcut in the Shortcuts app and comes back: DeckOut reads the list again.
    try offer(["Morning", "Evening"])
    await model.becameActive()
    #expect(await until { model.shortcutNames == ["Evening", "Morning"] })

    // A picker appearing again reads it again too.
    try offer(["Morning", "Evening", "Night"])
    model.loadShortcutNames()
    #expect(await until { model.shortcutNames == ["Evening", "Morning", "Night"] })
}

@MainActor @Test func theListIsntReadUntilAPickerNeedsIt() async throws {   // T-175
    let model = try previewModel(.empty, deck: .n4, selection: nil)
    model.shortcutsTool = "/nonexistent/shortcuts"
    // Coming to the front never starts the first read: a person who never picks a Shortcut never runs the tool.
    await model.becameActive()
    #expect(model.shortcutNames == nil)
}
