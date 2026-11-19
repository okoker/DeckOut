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

@Test func liveImagesKeyedByBlock() async throws {                   // T-106
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deckcore-live-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let path = folder.appendingPathComponent("config.json").path
    func config(active: String) -> AppConfig {
        AppConfig(n4: N4Section(
            brightness: 50, knobs: [:], swipe: nil, lockPhoto: nil,
            presets: [N4Preset(name: "Work", keys: [:], strip: ["1": StripBlockConfig(type: .internet),
                                                                  "3": StripBlockConfig(type: .internet),
                                                                  "4": StripBlockConfig(type: .volume)]),
                      N4Preset(name: "Music", keys: [:], strip: ["3": StripBlockConfig(type: .load)])],
            activePreset: active))
    }
    try ConfigFile.save(config(active: "Work"), to: path)
    nonisolated(unsafe) let agent = Agent(configPath: path, environment: ShellEnvironment(fixed: ["PATH": "/usr/bin:/bin"]))
    nonisolated(unsafe) var pushes = 0
    agent.onLiveStripChange = { pushes += 1 }

    let internet = Data([0xFF, 0xD8, 0x01]), volume = Data([0xFF, 0xD8, 0x04])
    let strip = await onMain { done in
        agent.receiveLiveImage(.internet, internet)
        agent.receiveLiveImage(.volume, volume)
        done(agent.liveStrip())
    }
    #expect(strip.images == ["1": internet, "3": internet, "4": volume])
    #expect(pushes == 2)

    // Another preset goes live: only its live blocks keep an image (none yet for its load block).
    try ConfigFile.save(config(active: "Music"), to: path)
    let _: ReloadResult = await onMain { done in agent.reload(completion: done) }
    let after = await onMain { done in done(agent.liveStrip()) }
    #expect(after.images.isEmpty)
}

@Test func restartExitsAfterTheReply() async {                       // T-104
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("deckcore-none-\(UUID().uuidString).json").path
    nonisolated(unsafe) var exited = false
    let agent = Agent(configPath: path, environment: ShellEnvironment(fixed: ["PATH": "/usr/bin:/bin"]),
                      exit: { exited = true })
    _ = await onMain { (done: @escaping (Bool) -> Void) in agent.restart(); done(true) }
    #expect(!exited)    // not at once: the reply must get out first
    try? await Task.sleep(nanoseconds: 600_000_000)
    #expect(exited)
}

@Test func appReloadLogsOneLine() async throws {                     // T-123
    // The app saves on every edit; each reload it asks for logs one line, not the whole config (plan 1 review M8).
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deckcore-log-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let path = folder.appendingPathComponent("config.json").path
    try ConfigFile.save(AppConfig(n4: N4Section(brightness: 50, knobs: [:], swipe: nil, lockPhoto: nil,
                                                presets: [N4Preset(name: "Work", keys: [:], strip: [:])],
                                                activePreset: "Work")), to: path)
    nonisolated(unsafe) var lines: [String] = []
    nonisolated(unsafe) let agent = Agent(configPath: path, environment: ShellEnvironment(fixed: ["PATH": "/usr/bin:/bin"]),
                                          log: { lines.append($0) })
    lines.removeAll()   // the start-up summary
    let _: ReloadResult = await onMain { done in agent.reload(completion: done) }
    #expect(lines.contains("Config reloaded (from the app): N4 Work"))
    #expect(!lines.contains { $0.hasPrefix("Config loaded from") })
    #expect(lines.count <= 2)
}
