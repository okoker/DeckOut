import Foundation
import Testing
@testable import DeckCore

@Test func scriptRunsAsGivenWithTheEnvironment() async throws {     // T-086
    // A folder and file name with spaces, quotes and `$`: the path must reach the program as given.
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("deckcore-\(UUID().uuidString)")
        .appendingPathComponent(#"my "odd" $dir"#)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let script = folder.appendingPathComponent("run me.sh").path
    try Data("#!/bin/sh\nprintf '%s' \"$FAKE_VAR\"\n".utf8).write(to: URL(fileURLWithPath: script))
    #expect(chmod(script, 0o755) == 0)

    let dispatcher = ActionDispatcher(config: .empty, brightness: nil,
                                      environment: ShellEnvironment(fixed: ["FAKE_VAR": "hello", "PATH": "/usr/bin:/bin"]))
    let result = await withCheckedContinuation { (done: CheckedContinuation<ActionResult, Never>) in
        dispatcher.execute(ResolvedAction(action: "script:" + script, step: nil)) { done.resume(returning: $0) }
    }
    #expect(result.stdout == "hello")
    #expect(result.exitStatus == 0)
    #expect(result.error == nil)
}
