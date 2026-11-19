import DeckCore
import Foundation
import Testing
@testable import DeckOutKit

private func tempFile(_ name: String, mode: mode_t) throws -> String {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deckout-files-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let path = folder.appendingPathComponent(name).path
    try Data("#!/bin/sh\necho hi\n".utf8).write(to: URL(fileURLWithPath: path))
    chmod(path, mode)
    return path
}

@Test func findsWhatIsGone() throws {   // T-130
    let script = try tempFile("go.sh", mode: 0o755)
    var config = AppConfig.empty
    config.setButton(.n4, "key_1", ButtonConfig(action: "app:/Applications/Gone Away.app"))
    config.setButton(.n4, "key_2", ButtonConfig(action: "open:/nonexistent/folder"))
    config.setButton(.n4, "key_3", ButtonConfig(action: "script:\(script)"))
    config.setButton(.n4, "key_4", ButtonConfig(action: "media_next", icon: "/nonexistent/icon.png"))
    config.setButton(.n4, "key_5", ButtonConfig(action: "app:/System/Applications/Notes.app"))
    config.setStripBlock("2", StripBlockConfig(type: .picture, icon: "/nonexistent/p.png"))
    config.setKnob(.n4, "knob_1", KnobConfig(rotate: KnobAction(action: "system_volume", step: 2),
                                              press: KnobAction(action: "script:/nonexistent/s.sh")))
    let problems = MissingFiles.check(config, deck: .n4)
    #expect(problems["key_1"] == "The app isn't there any more")
    #expect(problems["key_2"] == "The file or folder isn't there any more")
    #expect(problems["key_3"] == nil)
    #expect(problems["key_4"] == "The icon file isn't there any more")
    #expect(problems["key_5"] == nil)
    #expect(problems["2"] == "The picture isn't there any more")
    #expect(problems["knob_1"] == "The script isn't there any more")
    #expect(problems.count == 5)
}

@Test func scriptWarnings() throws {   // T-131
    let runnable = try tempFile("ok.sh", mode: 0o755)
    let plain = try tempFile("plain.sh", mode: 0o644)
    #expect(MissingFiles.scriptProblem(runnable) == nil)
    #expect(MissingFiles.scriptProblem(plain) == .notExecutable)
    #expect(MissingFiles.scriptProblem("/nonexistent/x.sh") == .missing)

    // Fix it on request: user execute bit only.
    #expect(MissingFiles.makeExecutable(plain))
    var st = stat()
    stat(plain, &st)
    #expect(st.st_mode & 0o777 == 0o744)
    #expect(MissingFiles.scriptProblem(plain) == nil)

    // A script in a folder macOS guards: a note (by path only; nothing there is read).
    for path in ["/Users/x/Desktop/a.sh", "/Users/x/Documents/b/c.sh", "/Users/x/Downloads/d.sh",
                 "/Users/x/Library/Mobile Documents/com~apple~CloudDocs/e.sh"] {
        #expect(MissingFiles.guardedFolderNote(path, home: "/Users/x") != nil, "\(path)")
    }
    #expect(MissingFiles.guardedFolderNote("/Users/x/bin/f.sh", home: "/Users/x") == nil)
}
