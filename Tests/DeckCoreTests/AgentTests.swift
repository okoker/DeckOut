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
        brightness: 50, swipe: nil, lockPhoto: nil,
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
            brightness: 50, swipe: nil, lockPhoto: nil,
            presets: [N4Preset(name: "Work", keys: [:], strip: ["1": StripBlockConfig(type: .internet),
                                                                  "3": StripBlockConfig(type: .internet),
                                                                  "4": StripBlockConfig(type: .volume)]),
                      N4Preset(name: "Music", keys: [:], strip: ["3": StripBlockConfig(type: .load)])],
            activePreset: active))
    }
    try ConfigFile.save(config(active: "Work"), to: path)
    nonisolated(unsafe) let agent = Agent(configPath: path, environment: ShellEnvironment(fixed: ["PATH": "/usr/bin:/bin"]))

    let internet = Data([0xFF, 0xD8, 0x01]), volume = Data([0xFF, 0xD8, 0x04])
    let strip = await onMain { done in
        agent.receiveLiveImages([.internet: internet, .volume: volume])
        done(agent.liveStrip())
    }
    #expect(strip.images == ["1": internet, "3": internet, "4": volume])

    // Another preset goes live: only its live blocks keep an image (none yet for its load block).
    try ConfigFile.save(config(active: "Music"), to: path)
    let _: ReloadResult = await onMain { done in agent.reload(completion: done) }
    let after = await onMain { done in done(agent.liveStrip()) }
    #expect(after.images.isEmpty)
}

@Test func aRedrawPushesTheLiveStripOnce() async throws {             // T-163
    // A redraw of an N4 with three live blocks hands the agent all three images at once: the app hears one push, not
    // three (BL-009). A later reading of one block keeps the others' images.
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deckcore-redraw-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let path = folder.appendingPathComponent("config.json").path
    try ConfigFile.save(AppConfig(n4: N4Section(
        brightness: 50, swipe: nil, lockPhoto: nil,
        presets: [N4Preset(name: "Work", keys: [:], strip: ["1": StripBlockConfig(type: .internet),
                                                            "2": StripBlockConfig(type: .load),
                                                            "4": StripBlockConfig(type: .volume)])],
        activePreset: "Work")), to: path)
    nonisolated(unsafe) let agent = Agent(configPath: path, environment: ShellEnvironment(fixed: ["PATH": "/usr/bin:/bin"]))
    nonisolated(unsafe) var pushes = 0
    agent.onLiveStripChange = { pushes += 1 }

    let internet = Data([0xFF, 0xD8, 0x01]), load = Data([0xFF, 0xD8, 0x02]), volume = Data([0xFF, 0xD8, 0x04])
    let drawn = await onMain { done in
        agent.receiveLiveImages([.internet: internet, .load: load, .volume: volume])
        done(agent.liveStrip())
    }
    #expect(drawn.images == ["1": internet, "2": load, "4": volume])
    #expect(pushes == 1)

    let louder = Data([0xFF, 0xD8, 0x05])
    let after = await onMain { done in
        agent.receiveLiveImages([.volume: louder])
        done(agent.liveStrip())
    }
    #expect(after.images == ["1": internet, "2": load, "4": louder])
    #expect(pushes == 2)
}

@Test func restartExitsAfterTheReply() async {                       // T-104
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("deckcore-none-\(UUID().uuidString).json").path
    nonisolated(unsafe) var exited = false
    let agent = Agent(configPath: path, environment: ShellEnvironment(fixed: ["PATH": "/usr/bin:/bin"]),
                      exit: { exited = true })
    _ = await onMain { (done: @escaping (Bool) -> Void) in agent.restart(); done(true) }
    #expect(!exited)    // not at once: the reply must get out first
    for _ in 0..<100 where !exited { try? await Task.sleep(nanoseconds: 100_000_000) }   // the main thread may be busy
    #expect(exited)
}

@Test func appReloadLogsOneLine() async throws {                     // T-123
    // The app saves on every edit; each reload it asks for logs one line, not the whole config (plan 1 review M8).
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deckcore-log-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let path = folder.appendingPathComponent("config.json").path
    try ConfigFile.save(AppConfig(n4: N4Section(brightness: 50, swipe: nil, lockPhoto: nil,
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

// MARK: - Next preset (BL-033)

/// `config` saved in a new temp folder; the file's path.
private func savedConfig(_ config: AppConfig) throws -> String {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deckcore-next-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let path = folder.appendingPathComponent("config.json").path
    try ConfigFile.save(config, to: path)
    return path
}

/// Runs `switchToNextPreset` on the main thread, as the daemon's input does.
private func next(_ agent: Agent, _ deck: DeckKind) async {
    _ = await onMain { (done: @escaping (Bool) -> Void) in agent.switchToNextPreset(deck); done(true) }
}

@Test func nextPresetStepsAndSaves() async throws {                  // T-189
    // A swipe set to next_preset: the deck's next preset in menu order, wrapping round, saved to the file so the
    // agent, the app (a status push) and a restart all follow.
    func config(live: String, musicKey: ButtonConfig? = nil) -> AppConfig {
        AppConfig(n3: N3Section(brightness: 50,
                                presets: [N3Preset(name: "A", buttons: [:]), N3Preset(name: "B", buttons: [:])],
                                activePreset: "A"),
                  n4: N4Section(brightness: 50, swipe: nil, lockPhoto: nil,
                                presets: [N4Preset(name: "Work", keys: [:], strip: [:]),
                                          N4Preset(name: "Music", keys: musicKey.map { ["key_1": $0] } ?? [:], strip: [:]),
                                          N4Preset(name: "Games", keys: [:], strip: [:])],
                                activePreset: live))
    }
    let path = try savedConfig(config(live: "Games"))
    nonisolated(unsafe) var lines: [String] = []
    nonisolated(unsafe) let agent = Agent(configPath: path, environment: ShellEnvironment(fixed: ["PATH": "/usr/bin:/bin"]),
                                          log: { lines.append($0) })
    nonisolated(unsafe) var changes = 0
    agent.onStatusChange = { changes += 1 }
    func liveInFile() throws -> String? { try ConfigFile.load(at: path).get().n4?.activePreset }

    // From the last preset it wraps round to the first.
    await next(agent, .n4)
    #expect(try liveInFile() == "Work")
    let status = await onMain { done in done(agent.status()) }
    #expect(status.activePresets["n4"] == "Work")
    #expect(changes == 1)
    #expect(lines.contains("Next preset: N4 Games → Work"))

    // Two in a row: one step each.
    await next(agent, .n4)
    #expect(try liveInFile() == "Music")
    await next(agent, .n4)
    #expect(try liveInFile() == "Games")

    // A hand edit saved but not reloaded is built on, not lost: the file is live on Music, with a new key.
    try ConfigFile.save(config(live: "Music", musicKey: ButtonConfig(action: "media_next")), to: path)
    await next(agent, .n4)
    let edited = try ConfigFile.load(at: path).get()
    #expect(edited.n4?.activePreset == "Games")
    #expect(edited.n4?.presets[1].keys["key_1"]?.action == "media_next")

    // An active_preset naming no preset counts as the first.
    try ConfigFile.save(config(live: "Gone"), to: path)
    await next(agent, .n4)
    #expect(try liveInFile() == "Music")

    // The N3 steps its own presets.
    await next(agent, .n3)
    #expect(try ConfigFile.load(at: path).get().n3?.activePreset == "B")
}

@Test func nextPresetNeverWritesAFileItCantUse() async throws {      // T-190
    // The agent writes the config only to save a switch, and never over a file it can't use: the file's bytes and
    // mode stay, no `.before-app` copy appears, the live preset stays, and the log says why.
    func n4(_ names: [String]) -> N4Section {
        N4Section(brightness: 50, swipe: nil, lockPhoto: nil,
                  presets: names.map { N4Preset(name: $0, keys: [:], strip: [:]) }, activePreset: names[0])
    }
    let good = AppConfig(n4: n4(["Work", "Music"]))
    let n3Only = AppConfig(n3: N3Section(brightness: 50,
                                         presets: [N3Preset(name: "A", buttons: [:]), N3Preset(name: "B", buttons: [:])],
                                         activePreset: "A"))
    // The file the agent starts from, what happens to it before the swipe, and the line the swipe logs.
    let cases: [(name: String, start: AppConfig, change: (String) throws -> Void, line: (String) -> Bool)] = [
        ("doesn't parse", good, { try Data("{ broken".utf8).write(to: URL(fileURLWithPath: $0)) },
         { $0.hasPrefix("Next preset: ") && $0.hasSuffix("— preset not changed") }),
        ("group-writable", good, { #expect(chmod($0, 0o664) == 0) },
         { $0.hasPrefix("Next preset: ") && $0.hasSuffix("— preset not changed") }),
        ("one preset", AppConfig(n4: n4(["Work"])), { _ in },
         { $0 == "Next preset: N4 has one preset, nothing to switch to" }),
        ("no N4", n3Only, { _ in },
         { $0 == "Next preset: no N4 in the config" }),
    ]
    for c in cases {
        let path = try savedConfig(c.start)
        nonisolated(unsafe) var lines: [String] = []
        nonisolated(unsafe) let agent = Agent(configPath: path, environment: ShellEnvironment(fixed: ["PATH": "/usr/bin:/bin"]),
                                              log: { lines.append($0) })
        try c.change(path)
        let bytes = FileManager.default.contents(atPath: path)
        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        let before = await onMain { done in done(agent.status()) }

        await next(agent, .n4)

        #expect(FileManager.default.contents(atPath: path) == bytes, "\(c.name)")
        let modeAfter = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        #expect(modeAfter == mode, "\(c.name)")
        #expect(!FileManager.default.fileExists(atPath: path + ".before-app"), "\(c.name)")
        let after = await onMain { done in done(agent.status()) }
        #expect(after.activePresets == before.activePresets, "\(c.name)")
        #expect(lines.contains(where: c.line), "\(c.name): \(lines)")
    }
}

@Test func nextPresetAsksTheAgent() async {                          // T-191
    // The daemon hands next_preset (on a swipe, or on a knob press set by hand) to the agent, which owns the file,
    // instead of the dispatcher; on a locked Mac, never.
    let config = AppConfig(n4: N4Section(
        brightness: 50, swipe: .nextPreset, lockPhoto: nil,
        presets: [N4Preset(name: "Work", keys: [:], strip: [:], knobs: [
            "knob_1": KnobConfig(rotate: KnobAction(action: "system_volume"), press: KnobAction(action: "next_preset")),
        ])],
        activePreset: "Work"))
    for locked in [false, true] {
        nonisolated(unsafe) let daemon = Daemon(config: config, environment: ShellEnvironment(fixed: [:]),
                                                lockMonitor: LockMonitor(isLockedNow: { locked }))
        nonisolated(unsafe) var asked: [DeckKind] = []
        daemon.onNextPreset = { asked.append($0) }
        _ = await onMain { (done: @escaping (Bool) -> Void) in
            daemon.handle(.n4, .swipe)
            daemon.handle(.n4, .knobDown("knob_1"))
            done(true)
        }
        #expect(asked == (locked ? [] : [.n4, .n4]), "locked: \(locked)")
    }
}
