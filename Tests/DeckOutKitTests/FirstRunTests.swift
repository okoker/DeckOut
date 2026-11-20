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
    var launchctl: [[String]] = []
    await second.retireOldController { launchctl.append($0); return 0 }
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
