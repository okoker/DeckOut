import Foundation
import Testing
@testable import DeckCore

@Test func capturesOutputAndExitStatus() {                          // T-077
    let result = ProcessRunner.run(executable: "/bin/sh", arguments: ["-c", "echo out; echo err >&2; exit 3"],
                                   environment: nil)
    #expect(result.stdout == "out\n")
    #expect(result.stderr == "err\n")
    #expect(result.exitStatus == 3)
    #expect(result.error == nil)

    // Megabytes of output are capped, so neither the log nor an XPC reply swells.
    let big = ProcessRunner.run(executable: "/bin/sh", arguments: ["-c", "head -c 200000 /dev/zero | tr '\\0' a"],
                                environment: nil)
    #expect(big.stdout.count == ProcessRunner.outputCap + "\n…(truncated)".count)
    #expect(big.stdout.hasSuffix("\n…(truncated)"))
    #expect(big.exitStatus == 0)
}

@Test func timeoutAndMissingExecutableReportErrors() {              // T-078
    let started = Date()
    let slow = ProcessRunner.run(executable: "/bin/sleep", arguments: ["5"], environment: nil, timeout: 0.3)
    #expect(Date().timeIntervalSince(started) < 2)
    #expect(slow.error?.contains("timed out") == true)

    let missing = ProcessRunner.run(executable: "/no/such/tool", arguments: [], environment: nil)
    #expect(missing.error != nil)
    #expect(missing.exitStatus == nil)
}
