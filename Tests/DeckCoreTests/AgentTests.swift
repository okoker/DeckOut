import Foundation
import Testing
@testable import DeckCore

// The agent is never started here: `start()` opens the decks. Its reloads and status work without that.

private func onMain<T>(_ body: @escaping (@escaping (T) -> Void) -> Void) async -> T {
    await withCheckedContinuation { (done: CheckedContinuation<T, Never>) in
        DispatchQueue.main.async { body { done.resume(returning: $0) } }
    }
}

@Test func agentReloadReportsAndClearsTheProblem() async throws {  // T-091
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deckcore-agent-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let path = folder.appendingPathComponent("config.json").path

    nonisolated(unsafe) let agent = Agent(configPath: path, environment: ShellEnvironment(fixed: ["PATH": "/usr/bin:/bin"]))
    nonisolated(unsafe) var changes = 0
    agent.onStatusChange = { changes += 1 }

    // No file yet: the agent runs blank and says why.
    let blank = await onMain { done in done(agent.status()) }
    #expect(blank.configProblem == "No config yet at \(path)")
    #expect(blank.decks == [])
    #expect(blank.activePresets == [:])
    #expect(blank.environment == EnvironmentStatus(state: .resolved, detail: nil))

    // A config appears: the reload loads it and clears the problem.
    let config = AppConfig(n4: N4Section(
        brightness: 50, knobs: [:], swipe: nil, lockPhoto: nil,
        presets: [N4Preset(name: "Work", keys: [:], strip: [:]), N4Preset(name: "Music", keys: [:], strip: [:])],
        activePreset: "Music"))
    try ConfigFile.save(config, to: path)
    let loaded: ReloadResult = await onMain { done in agent.reload(completion: done) }
    #expect(loaded == ReloadResult(loaded: true, problem: nil))
    let running = await onMain { done in done(agent.status()) }
    #expect(running.configProblem == nil)
    #expect(running.activePresets == ["n4": "Music"])

    // The file breaks: the previous config stays, and the problem is reported.
    try Data("{ broken".utf8).write(to: URL(fileURLWithPath: path))
    let failed: ReloadResult = await onMain { done in agent.reload(completion: done) }
    #expect(failed.loaded == false)
    #expect(failed.problem?.contains("doesn't load") == true)
    let kept = await onMain { done in done(agent.status()) }
    #expect(kept.activePresets == ["n4": "Music"])
    #expect(kept.configProblem == failed.problem)
    #expect(changes == 2)
}
