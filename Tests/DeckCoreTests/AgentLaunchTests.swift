import Foundation
import Testing
@testable import DeckCore

// How the agent starts: which config it reads, where its log goes, and the version it reports.

@Test func configPathOrder() {   // T-097
    let none: (String) -> Bool = { _ in false }
    // --config wins over everything.
    #expect(AgentLaunch.configPath(arguments: ["x", "--config", "/tmp/c.json"], identity: .dev, home: "/Users/x",
                                   execDir: "/bin", exists: none) == "/tmp/c.json")
    #expect(AgentLaunch.configPath(arguments: ["x", "--config"], identity: .dev, home: "/Users/x",
                                   execDir: "/bin", exists: none) == nil)
    // Inside DeckOut: the identity's file, even when it doesn't exist yet (the app will write it).
    #expect(AgentLaunch.configPath(arguments: ["x"], identity: .dev, home: "/Users/x", execDir: "/bin",
                                   exists: none) == "/Users/x/.deckout-dev/config.json")
    #expect(AgentLaunch.configPath(arguments: ["x"], identity: .release, home: "/Users/x", execDir: "/bin",
                                   exists: { _ in true }) == "/Users/x/.deckout/config.json")
    // A hand install: today's candidates, the first that exists.
    #expect(AgentLaunch.configPath(arguments: ["x"], identity: nil, home: "/Users/x", execDir: "/opt/sdc",
                                   exists: { $0 == "/opt/sdc/config.json" }) == "/opt/sdc/config.json")
}

@Test func reloadNotificationIsPerDeckOut() {   // T-194
    // One name per DeckOut, so `--post-reload` for DeckOut Dev never reloads DeckOut; a hand install has its own.
    #expect(AgentLaunch.reloadNotification(identity: .release) == "io.github.okoker.deckout.agent.reload")
    #expect(AgentLaunch.reloadNotification(identity: .dev) == "io.github.okoker.deckout.dev.agent.reload")
    #expect(AgentLaunch.reloadNotification(identity: nil) == "io.github.okoker.deckout.reload")
}

@Test func logRollsOverLimit() throws {   // T-098
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deckcore-log-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let log = folder.appendingPathComponent("agent.log").path

    // Under the limit: left alone.
    try Data(repeating: 65, count: 100).write(to: URL(fileURLWithPath: log))
    AgentLaunch.rollLog(at: log, limit: 1000)
    #expect(FileManager.default.fileExists(atPath: log))
    #expect(!FileManager.default.fileExists(atPath: log + ".1"))

    // Over it: moved aside (replacing an older .1), so the new run starts a fresh file.
    try Data("old".utf8).write(to: URL(fileURLWithPath: log + ".1"))
    try Data(repeating: 66, count: 2000).write(to: URL(fileURLWithPath: log))
    AgentLaunch.rollLog(at: log, limit: 1000)
    #expect(!FileManager.default.fileExists(atPath: log))
    let moved = try Data(contentsOf: URL(fileURLWithPath: log + ".1"))
    #expect(moved.count == 2000)

    // No log yet: nothing happens.
    AgentLaunch.rollLog(at: folder.appendingPathComponent("none.log").path, limit: 1000)
}

@Test func statusCarriesBuildFromLaunch() throws {   // T-099
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("deckcore-none-\(UUID().uuidString).json").path
    let agent = Agent(configPath: path, environment: ShellEnvironment(fixed: ["PATH": "/usr/bin:/bin"]),
                      version: "2.0.0", build: "261119.230000")
    let status = agent.status()
    #expect(status.version == "2.0.0")
    #expect(status.build == "261119.230000")

    // An older agent's status has no build: it decodes, with nil.
    let old = #"{"version":"1.0","decks":[],"activePresets":{},"environment":{"state":"resolved"}}"#
    let decoded = try JSONDecoder().decode(AgentStatus.self, from: Data(old.utf8))
    #expect(decoded.build == nil)
}
