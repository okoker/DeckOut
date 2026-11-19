import DeckCore
import Foundation
import Testing
@testable import DeckOutKit

// The app's link to its agent, against a stub agent behind an in-process listener (no launchd, no decks).

final class StubAgent: AgentControl, @unchecked Sendable {
    var build: String?
    var restarts = 0
    var strip = LiveStrip(images: [:])
    var onStatusChange: (() -> Void)?
    var onLiveStripChange: (() -> Void)?

    init(build: String?) { self.build = build }

    func status() -> AgentStatus {
        AgentStatus(version: "2.0.0", build: build, decks: ["n4"], activePresets: ["n4": "Work"], configProblem: nil,
                    environment: EnvironmentStatus(state: .resolved, detail: nil))
    }
    func reload(completion: @escaping (ReloadResult) -> Void) { completion(ReloadResult(loaded: true, problem: nil)) }
    func test(_ request: TestRequest, completion: @escaping (ActionResult) -> Void) {
        completion(ActionResult(exitStatus: 0, stdout: "", stderr: "", error: nil))
    }
    func showLockPhoto(_ framing: LockPhotoConfig?) {}
    func refreshEnvironment(completion: @escaping (EnvironmentStatus) -> Void) {
        completion(EnvironmentStatus(state: .resolved, detail: nil))
    }
    func restart() { restarts += 1 }
    func liveStrip() -> LiveStrip { strip }
    func requestAccessibility() -> Bool { false }
}

/// A listener serving a stub agent; `connect()` opens a client connection to it.
final class StubServer: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    let agent: StubAgent
    let service: AgentService
    let listener = NSXPCListener.anonymous()
    private(set) var connects = 0
    private(set) var serverSide: [NSXPCConnection] = []

    init(agent: StubAgent) {
        self.agent = agent
        service = AgentService(control: agent, peerRequirement: nil)
        super.init()
        listener.delegate = self
        listener.resume()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        serverSide.append(connection)
        return service.listener(listener, shouldAcceptNewConnection: connection)
    }

    func connect() -> NSXPCConnection {
        connects += 1
        return NSXPCConnection(listenerEndpoint: listener.endpoint)
    }
}

/// Waits (polling the main actor) until `condition` holds; false after 10 s (long: snapshot tests keep the main
/// thread busy for seconds in a full run).
@MainActor func until(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<1000 {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return condition()
}

@MainActor @Test func restartsAnOlderAgentOnce() async {   // T-111
    let server = StubServer(agent: StubAgent(build: "old"))
    let link = AgentLink(connect: server.connect, appBuild: "new", retryDelay: 0.05)
    link.start()
    #expect(await until { server.agent.restarts == 1 })

    // The agent that comes back is still the old build (e.g. the app wasn't really replaced): say so, no loop.
    DispatchQueue.main.async { server.agent.onStatusChange?() }
    #expect(await until { link.state == .versionMismatch(agent: "old", app: "new") })
    try? await Task.sleep(nanoseconds: 100_000_000)
    #expect(server.agent.restarts == 1)

    // An agent from before builds were reported counts as older.
    let older = StubServer(agent: StubAgent(build: nil))
    let link2 = AgentLink(connect: older.connect, appBuild: "new", retryDelay: 0.05)
    link2.start()
    #expect(await until { older.agent.restarts == 1 })
}

@MainActor @Test func hearsStatusAndStrip() async {   // T-112
    let server = StubServer(agent: StubAgent(build: "same"))
    let link = AgentLink(connect: server.connect, appBuild: "same", retryDelay: 0.05)
    link.start()
    #expect(await until { link.state == .connected })
    #expect(link.status?.decks == ["n4"])
    #expect(server.agent.restarts == 0)

    let strip = LiveStrip(images: ["2": Data([0xFF, 0xD8, 2])])
    DispatchQueue.main.async {
        server.agent.strip = strip
        server.agent.onLiveStripChange?()
    }
    #expect(await until { link.liveStrip == strip })

    // The agent goes away (crash, restart): the link reconnects and asks again.
    for connection in server.serverSide { connection.invalidate() }
    #expect(await until { server.connects >= 2 && link.state == .connected })
}

@MainActor @Test func silentAgentIsReportedOnce() async {   // T-112
    // A connection nobody answers: not answering, and the hook (register again) runs once.
    let listener = NSXPCListener.anonymous()
    final class Mute: NSObject, NSXPCListenerDelegate {
        func listener(_ l: NSXPCListener, shouldAcceptNewConnection c: NSXPCConnection) -> Bool {
            c.exportedInterface = NSXPCInterface(with: AgentXPC.self)
            c.exportedObject = MuteAgent()
            c.resume()
            return true
        }
    }
    let mute = Mute()
    listener.delegate = mute
    listener.resume()
    var hooks = 0
    var connects = 0
    let link = AgentLink(connect: { connects += 1; return NSXPCConnection(listenerEndpoint: listener.endpoint) },
                         appBuild: "x", retryDelay: 0.05, answerTimeout: 0.2)
    link.onNotAnswering = { hooks += 1 }
    link.start()
    #expect(await until { link.state == .notAnswering })
    try? await Task.sleep(nanoseconds: 500_000_000)
    #expect(hooks == 1)

    // After the agent is registered afresh, the link starts over on a new connection.
    link.reconnect()
    #expect(await until { connects == 2 })
}

/// Takes every call and never replies.
final class MuteAgent: NSObject, AgentXPC {
    func status(reply: @escaping (Data) -> Void) {}
    func reload(reply: @escaping (Data) -> Void) {}
    func test(_ request: Data, reply: @escaping (Data) -> Void) {}
    func showLockPhoto(_ framing: Data?, reply: @escaping () -> Void) {}
    func refreshEnvironment(reply: @escaping (Data) -> Void) {}
    func restart(reply: @escaping () -> Void) {}
    func liveStrip(reply: @escaping (Data) -> Void) {}
    func requestAccessibility(reply: @escaping (Bool) -> Void) {}
}

/// Refuses every connection, like an agent that can't check its peer, or a Mach service that isn't there.
final class RefusingServer: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    let listener = NSXPCListener.anonymous()
    private(set) var connects = 0
    override init() {
        super.init()
        listener.delegate = self
        listener.resume()
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool { false }
    func connect() -> NSXPCConnection {
        connects += 1
        return NSXPCConnection(listenerEndpoint: listener.endpoint)
    }
}

@MainActor @Test func refusedLinkIsReportedAndBacksOff() async {   // T-112 (review I1)
    // Each connection fails at once, so no single one ever times out: the link still says so, once, and doesn't
    // hammer the agent once a second (or faster) forever.
    let server = RefusingServer()
    var hooks = 0
    let link = AgentLink(connect: server.connect, appBuild: "x", retryDelay: 0.05, answerTimeout: 0.3)
    link.onNotAnswering = { hooks += 1 }
    link.start()
    #expect(await until { link.state == .notAnswering })
    try? await Task.sleep(nanoseconds: 1_500_000_000)
    #expect(hooks == 1)
    #expect(server.connects < 12, "backs off: \(server.connects) connects in ~2 s")
    #expect(link.state == .notAnswering)
}

@MainActor @Test func droppedAgentIsNotShownAsRunning() async {   // T-112 (review I2)
    // Connected, then the agent goes and doesn't come back: after a short grace (a restart takes a moment) the
    // link forgets the old status, so the window stops drawing decks from it.
    let server = StubServer(agent: StubAgent(build: "same"))
    var refuse = false
    let refusing = RefusingServer()
    let link = AgentLink(connect: { refuse ? refusing.connect() : server.connect() }, appBuild: "same",
                         retryDelay: 0.05, answerTimeout: 5, dropGrace: 0.2)
    link.start()
    #expect(await until { link.state == .connected })
    refuse = true
    for connection in server.serverSide { connection.invalidate() }
    #expect(await until { link.state == .connecting })
    #expect(link.status != nil)          // within the grace: a restart shouldn't flash the screen
    #expect(await until { link.status == nil })
}

@Test func statusLineFollowsTheLink() {   // T-118 (review I2)
    let running = AppModel.statusLine(screen: .deck(.n4), linkState: .connected, status: nil, configProblem: nil)
    #expect(running.health == .good)
    let reconnecting = AppModel.statusLine(screen: .deck(.n4), linkState: .connecting, status: nil, configProblem: nil)
    #expect(reconnecting.health == .busy)
    #expect(reconnecting.text == "Reconnecting to the deck controller…")
}
