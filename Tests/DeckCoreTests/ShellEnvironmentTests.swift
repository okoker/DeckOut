import Foundation
import Testing
@testable import DeckCore

/// A stand-in for the user's login shell: `#!/bin/sh` plus `body`, executable, in a fresh temp folder.
/// It is called the way the real shell is: `-l -i -c <command>`.
private func fakeShell(_ body: String) throws -> String {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deckcore-shell-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let path = folder.appendingPathComponent("fakesh").path
    try Data("#!/bin/sh\n\(body)\n".utf8).write(to: URL(fileURLWithPath: path))
    #expect(chmod(path, 0o755) == 0)
    return path
}

private func refreshed(_ environment: ShellEnvironment) async {
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
        environment.refresh { done.resume() }
    }
}

@Test func readsTheEnvironmentBetweenMarkers() async throws {       // T-079
    let shell = try fakeShell(#"""
    echo "noise from rc"; shift 3; exec /usr/bin/env -i PATH=/fake/bin:/usr/bin:/bin FAKE_VAR=hello /bin/sh -c "$1"
    """#)
    let environment = ShellEnvironment(shell: shell, timeout: 5, base: ["PATH": "/usr/bin:/bin"])
    #expect(environment.state == .resolving)
    await refreshed(environment)
    #expect(environment.state == .resolved)
    #expect(environment.detail == nil)
    #expect(environment.current["FAKE_VAR"] == "hello")
    #expect(environment.current["PATH"] == "/fake/bin:/usr/bin:/bin")
}

@Test func fallsBackOnHangInputOrNoMarkers() async throws {         // T-080
    // Only the hang needs a short timeout; the others finish at once, and a short timeout under a busy test run
    // could cut them off first (seen 20/11/2026 with the app's snapshot tests running alongside).
    for (body, why, timeout) in [("sleep 30", "timed out", 0.5), ("read x; exit 0", "output", 2.5), ("echo hi; exit 1", "1", 2.5)] {
        let environment = ShellEnvironment(shell: try fakeShell(body), timeout: timeout, base: ["PATH": "/usr/bin:/bin"])
        let started = Date()
        await refreshed(environment)
        #expect(Date().timeIntervalSince(started) < 3, "\(body)")
        #expect(environment.state == .fellBack, "\(body)")
        #expect(environment.detail?.contains(why) == true, "\(body): \(environment.detail ?? "nil")")
        #expect(environment.current["PATH"]?.contains("/opt/homebrew/bin") == true, "\(body)")
    }
}

@Test func fallbackAddsHomebrewPaths() {                            // T-081
    #expect(ShellEnvironment.fallback(base: ["PATH": "/usr/bin:/bin"])["PATH"]
            == "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin")
    #expect(ShellEnvironment.fallback(base: ["PATH": "/opt/homebrew/bin:/usr/bin"])["PATH"]
            == "/opt/homebrew/bin:/usr/bin:/usr/local/bin")
    #expect(ShellEnvironment.fallback(base: ["HOME": "/Users/x"])["HOME"] == "/Users/x")
}
