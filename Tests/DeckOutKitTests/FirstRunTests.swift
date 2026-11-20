import DeckCore
import Foundation
import ServiceManagement
import Testing
@testable import DeckOutKit

private final class CountingService: ServiceManaging, @unchecked Sendable {
    var current: SMAppService.Status = .notRegistered
    var registers = 0, unregisters = 0
    var status: SMAppService.Status { current }
    func register() throws { registers += 1; current = .enabled }
    func unregister() async throws { unregisters += 1; current = .notRegistered }
}

@MainActor private func model(home: String, service: CountingService) throws -> AppModel {
    let path = try tempConfigPath()
    let store = ConfigStore(path: path, reload: {})
    return AppModel(identity: .dev, appBuild: "t", link: nil, store: store,
                    registrar: AgentRegistrar(service: service, sleep: { _ in }), home: home)
}

@MainActor @Test func oldControllerComesFirst() async throws {   // T-148
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("deckout-home-\(UUID().uuidString)").path
    try FileManager.default.createDirectory(atPath: home + "/Library/LaunchAgents", withIntermediateDirectories: true)
    let plist = OldController.plistPath(home: home)
    try Data("<plist/>".utf8).write(to: URL(fileURLWithPath: plist))

    // Found: the app asks before registering its own (two controllers would both act on every press).
    let service = CountingService()
    let app = try model(home: home, service: service)
    await app.launch(arguments: ["DeckOut"], bundlePath: "/Users/x/Applications/DeckOut Dev.app")
    #expect(app.screen == .oldController)
    #expect(service.registers == 0)

    // Not Now: registers anyway, and the status line keeps warning.
    await app.keepOldController()
    #expect(service.registers == 1)
    #expect(app.statusLine.text.contains("older deck controller"))

    // Retire It (another launch): launchd stops it, the plist moves aside, then DeckOut registers.
    try Data("<plist/>".utf8).write(to: URL(fileURLWithPath: plist))
    let fresh = CountingService()
    let second = try model(home: home, service: fresh)
    await second.launch(arguments: ["DeckOut"], bundlePath: "/Users/x/Applications/DeckOut Dev.app")
    nonisolated(unsafe) var launchctl: [[String]] = []
    await second.retireOldController { args in launchctl.append(args); return args.first == "print" ? 113 : 0 }
    #expect(launchctl.first?.first == "bootout")
    #expect(OldController.find(home: home) == nil)
    #expect(fresh.registers == 1)
    #expect(second.screen != .oldController)
}

@MainActor @Test func removalUnregisters() async throws {   // T-149
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("deckout-home-\(UUID().uuidString)").path
    let service = CountingService()
    let app = try model(home: home, service: service)
    await app.launch(arguments: ["DeckOut"], bundlePath: "/Users/x/Applications/DeckOut Dev.app")
    #expect(service.registers == 1)
    await app.stopAndRemove()
    #expect(service.unregisters == 1)
    #expect(app.screen == .removed)
    // Start Again registers it again.
    await app.startAgain()
    #expect(service.registers == 2)
    #expect(app.screen != .removed)
}

@MainActor @Test func removalStaysRemoved() async throws {   // T-149 (review C1)
    // With a real link: after Stop and Remove, the agent going away must not re-register it, nor coming back to
    // the app, nor the window opening again; only Start Again does.
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("deckout-home-\(UUID().uuidString)").path
    let service = CountingService()
    let server = StubServer(agent: StubAgent(build: "t"))
    var refuse = false
    let refusing = RefusingServer()
    let link = AgentLink(connect: { refuse ? refusing.connect() : server.connect() }, appBuild: "t",
                         retryDelay: 0.05, answerTimeout: 0.3, dropGrace: 0.1)
    let app = AppModel(identity: .dev, appBuild: "t", link: link,
                       store: ConfigStore(path: try tempConfigPath(), reload: {}),
                       registrar: AgentRegistrar(service: service, sleep: { _ in }), home: home)
    await app.launch(arguments: ["DeckOut"], bundlePath: "/Users/x/Applications/DeckOut Dev.app")
    #expect(await until { link.state == .connected })
    #expect(service.registers == 1)

    await app.stopAndRemove()
    #expect(service.unregisters == 1)
    #expect(app.screen == .removed)
    // The agent goes (as unregistering stops it) and nothing answers again.
    refuse = true
    for connection in server.serverSide { connection.invalidate() }
    try await Task.sleep(nanoseconds: 800_000_000)
    await app.becameActive()
    await app.launch(arguments: ["DeckOut"], bundlePath: "/Users/x/Applications/DeckOut Dev.app")
    #expect(service.registers == 1, "nothing registered it again")
    #expect(app.screen == .removed)

    await app.startAgain()
    #expect(service.registers == 2)
}
