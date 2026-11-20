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

/// A service whose unregister can be held until the test lets it go (T-164). The job goes out as unregister starts;
/// the call returns when macOS is done. Every call is logged, in order.
private final class HeldService: ServiceManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var current: SMAppService.Status
    private var holding = false
    private var held: [CheckedContinuation<Void, Never>] = []
    private var calls: [String] = []

    init(_ status: SMAppService.Status) { current = status }

    var status: SMAppService.Status { lock.withLock { current } }
    var log: [String] { lock.withLock { calls } }
    var heldCalls: Int { lock.withLock { held.count } }

    func register() throws { lock.withLock { calls.append("register"); current = .enabled } }
    func unregister() async throws {
        lock.withLock { calls.append("unregister"); current = .notRegistered }
        await withCheckedContinuation { (go: CheckedContinuation<Void, Never>) in
            let wait = lock.withLock { () -> Bool in
                if holding { held.append(go) }
                return holding
            }
            if !wait { go.resume() }
        }
        lock.withLock { calls.append("unregistered") }
    }

    /// From now, unregister waits until `release()`.
    func hold() { lock.withLock { holding = true } }
    func release() {
        let waiting = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            holding = false
            defer { held = [] }
            return held
        }
        waiting.forEach { $0.resume() }
    }
}

@MainActor private func model(home: String, service: ServiceManaging) throws -> AppModel {
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

@MainActor @Test func removalLandsLast() async throws {   // T-164
    // The agent stopped answering and its re-registration is under way (held inside its unregister) when the person
    // clicks Stop and Remove: the window says removed at once, the removal's unregister waits its turn and lands
    // last, and nothing registers the agent or restarts the link after it.
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("deckout-home-\(UUID().uuidString)").path
    let service = HeldService(.enabled)
    let server = StubServer(agent: StubAgent(build: "t"))
    let link = AgentLink(connect: server.connect, appBuild: "t", retryDelay: 0.05, answerTimeout: 600)
    let app = AppModel(identity: .dev, appBuild: "t", link: link,
                       store: ConfigStore(path: try tempConfigPath(), reload: {}),
                       registrar: AgentRegistrar(service: service, sleep: { _ in }), home: home)
    await app.launch(arguments: ["DeckOut"], bundlePath: "/Users/x/Applications/DeckOut Dev.app")
    #expect(await until { link.state == .connected })

    service.hold()
    let hook = try #require(link.onNotAnswering)
    let notAnswering = Task { await hook() }   // as the link runs it
    #expect(await until { service.heldCalls == 1 })
    let removal = Task { await app.stopAndRemove() }
    #expect(await until { app.removed })
    #expect(app.screen == .removed)
    try await Task.sleep(nanoseconds: 200_000_000)   // time for a call that doesn't wait its turn to reach macOS
    #expect(service.log == ["unregister"], "the removal waits for the re-registration under way")

    service.release()
    await notAnswering.value
    await removal.value
    #expect(service.log == ["unregister", "unregistered", "register", "unregister", "unregistered"])
    #expect(service.status == .notRegistered)
    #expect(app.removed)
    try await Task.sleep(nanoseconds: 300_000_000)
    #expect(link.state != .connected && link.status == nil, "the link stays stopped")
}

@MainActor @Test func registrationStepsTakeTurns() async throws {   // T-164
    // Try Again is under way (held inside its unregister) when the app comes to the front: the re-check waits its
    // turn, so macOS gets Try Again's calls together, then the re-check's (none: it finds the agent registered).
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("deckout-home-\(UUID().uuidString)").path
    let service = HeldService(.enabled)
    let app = try model(home: home, service: service)
    await app.launch(arguments: ["DeckOut"], bundlePath: "/Users/x/Applications/DeckOut Dev.app")
    #expect(app.registration == .enabled)

    service.hold()
    let tryAgain = Task { await app.tryAgain() }
    #expect(await until { service.heldCalls == 1 })
    let active = Task { await app.becameActive() }
    try await Task.sleep(nanoseconds: 200_000_000)   // time for a call that doesn't wait its turn to reach macOS
    #expect(service.log == ["unregister"], "the re-check waits for Try Again's step")

    service.release()
    await tryAgain.value
    await active.value
    #expect(service.log == ["unregister", "unregistered", "register"])
    #expect(app.registration == .enabled)
    // The line keeps going: the next step runs.
    await app.tryAgain()
    #expect(service.log.count == 6)
}
