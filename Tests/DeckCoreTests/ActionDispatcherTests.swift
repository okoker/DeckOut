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

@Test func programsDontWaitForEachOther() async {                   // T-092
    // A slow Test run (or a slow key) must not hold up the next key press.
    nonisolated(unsafe) let dispatcher = ActionDispatcher(config: .empty, brightness: nil,
                                                          environment: ShellEnvironment(fixed: ["PATH": "/usr/bin:/bin"]))
    let started = Date()
    let fastFinished = await withCheckedContinuation { (done: CheckedContinuation<TimeInterval, Never>) in
        dispatcher.execute(ResolvedAction(action: "shell:sleep 2", step: nil)) { _ in }
        dispatcher.execute(ResolvedAction(action: "shell:echo fast", step: nil)) { _ in
            done.resume(returning: Date().timeIntervalSince(started))
        }
    }
    #expect(fastFinished < 1, "the quick command waited \(fastFinished) s behind the slow one")
}

@Test func brightnessSaysWhyItCant() async {                         // T-152 (plan 6 review I2)
    func problem(_ displays: [DisplayConfig]?) async -> String? {
        let dispatcher = ActionDispatcher(config: AppConfig(displays: displays), brightness: nil,
                                          environment: ShellEnvironment(fixed: ["PATH": "/usr/bin:/bin"]))
        return await withCheckedContinuation { done in
            DispatchQueue.main.async {
                dispatcher.execute(ResolvedAction(action: "display_brightness", step: 5)) { done.resume(returning: $0.error) }
            }
        }
    }
    #expect(await problem(nil) == "Monitor brightness: no monitors set up (DeckOut → Settings → Monitors)")
    #expect(await problem([DisplayConfig(name: "Left", serial: "S")])
            == "Monitor brightness: monitors are set up but none could be reached (m1ddc missing, or no monitor answered)")
}
