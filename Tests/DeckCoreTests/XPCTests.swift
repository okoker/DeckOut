import Foundation
import Testing
@testable import DeckCore

// The XPC service, tested in-process: an anonymous listener, a client connection to its endpoint, and a stub in
// place of the agent. Nothing here touches the decks or launchd.

private final class StubControl: AgentControl, @unchecked Sendable {
    let statusValue = AgentStatus(version: "9.9", decks: ["n4"], activePresets: ["n4": "Music"], configProblem: nil,
                                  environment: EnvironmentStatus(state: .fellBack, detail: "timed out after 10 s"))
    let reloadValue = ReloadResult(loaded: false, problem: "Config doesn't load: stub")
    let testValue = ActionResult(exitStatus: 0, stdout: "hi\n", stderr: "", error: nil)
    var received: [TestRequest] = []
    var lockPhotos: [LockPhotoConfig?] = []
    var heardLockPhoto: ((LockPhotoConfig?) -> Void)?
    var onStatusChange: (() -> Void)?
    var onLiveStripChange: (() -> Void)?
    let liveStripValue = LiveStrip(images: ["1": Data([0xFF, 0xD8, 1]), "4": Data([0xFF, 0xD8, 4])])
    var restarted = false
    var heardRestart: (() -> Void)?
    var accessibilityRequests = 0

    func status() -> AgentStatus { statusValue }
    func reload(completion: @escaping (ReloadResult) -> Void) { completion(reloadValue) }
    func test(_ request: TestRequest, completion: @escaping (ActionResult) -> Void) {
        received.append(request)
        completion(testValue)
    }
    func showLockPhoto(_ framing: LockPhotoConfig?) {
        lockPhotos.append(framing)
        heardLockPhoto?(framing)
    }
    func refreshEnvironment(completion: @escaping (EnvironmentStatus) -> Void) { completion(statusValue.environment) }
    func restart() {
        restarted = true
        heardRestart?()
    }
    func liveStrip() -> LiveStrip { liveStripValue }
    func requestAccessibility() -> Bool {
        accessibilityRequests += 1
        return false
    }
}

private final class ClientSpy: NSObject, AgentClientXPC, @unchecked Sendable {
    var heard: ((Data) -> Void)?
    var heardStrip: ((Data) -> Void)?
    func statusChanged(_ status: Data) { heard?(status) }
    func liveStripChanged(_ strip: Data) { heardStrip?(strip) }
}

/// One listener + client pair. Keep it alive for the length of the test.
private final class Harness: @unchecked Sendable {
    let stub = StubControl()
    let service: AgentService
    let listener = NSXPCListener.anonymous()
    let client: NSXPCConnection

    init(exporting spy: ClientSpy? = nil, peerRequirement: (() -> String?)? = nil) {
        service = AgentService(control: stub, peerRequirement: peerRequirement)
        listener.delegate = service
        listener.resume()
        client = NSXPCConnection(listenerEndpoint: listener.endpoint)
        client.remoteObjectInterface = NSXPCInterface(with: AgentXPC.self)
        if let spy {
            client.exportedInterface = NSXPCInterface(with: AgentClientXPC.self)
            client.exportedObject = spy
        }
        client.resume()
    }

    deinit {
        client.invalidate()
        listener.invalidate()
    }

    /// Makes one call and waits for its reply; nil if the connection failed or nothing came within 10 s (long: the
    /// replies hop to the main thread, which the app's snapshot tests keep busy for seconds in a full run).
    /// `expectingError`: a failed connection is the expected outcome, not a test failure.
    func call<T>(expectingError: Bool = false, _ body: @escaping (AgentXPC, @escaping (T) -> Void) -> Void) async -> T? {
        await withCheckedContinuation { (done: CheckedContinuation<T?, Never>) in
            let once = Once(done)
            let proxy = client.remoteObjectProxyWithErrorHandler { error in
                if !expectingError { Issue.record("XPC error: \(error)") }
                once.resume(nil)
            } as! AgentXPC
            body(proxy) { once.resume($0) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) { once.resume(nil) }
        }
    }
}

/// Resumes a continuation exactly once, whichever of reply, error or timeout comes first.
private final class Once<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?
    init(_ continuation: CheckedContinuation<T?, Never>) { self.continuation = continuation }
    func resume(_ value: T?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

/// Counts what a client hears on its XPC queue, read from the test.
private final class Tally: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func add() {
        lock.lock()
        value += 1
        lock.unlock()
    }
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private func decode<T: Decodable>(_ type: T.Type, _ data: Data?) -> T? {
    data.flatMap { try? JSONDecoder().decode(type, from: $0) }
}

@Test func statusAndReloadRoundTrip() async {                       // T-087
    let harness = Harness()
    let status: Data? = await harness.call { proxy, reply in proxy.status(reply: reply) }
    #expect(decode(AgentStatus.self, status) == harness.stub.statusValue)
    let reload: Data? = await harness.call { proxy, reply in proxy.reload(reply: reply) }
    #expect(decode(ReloadResult.self, reload) == harness.stub.reloadValue)
}

@Test func testRequestReturnsTheActionResult() async throws {       // T-088
    let harness = Harness()
    let request = TestRequest(action: "shell:echo hi", step: nil)
    let body = try JSONEncoder().encode(request)
    let reply: Data? = await harness.call { proxy, reply in proxy.test(body, reply: reply) }
    #expect(decode(ActionResult.self, reply) == harness.stub.testValue)
    #expect(harness.stub.received == [request])
}

@Test func clientHearsStatusChanges() async {                       // T-089
    let spy = ClientSpy()
    let harness = Harness(exporting: spy)
    let first: Data? = await harness.call { proxy, reply in proxy.status(reply: reply) }   // signs the client up
    #expect(first != nil)
    let pushed: Data? = await harness.call { (_: AgentXPC, reply: @escaping (Data) -> Void) in
        spy.heard = reply
        DispatchQueue.main.async { harness.stub.onStatusChange?() }
    }
    #expect(decode(AgentStatus.self, pushed) == harness.stub.statusValue)
}

@Test func badRequestGetsAnError() async {                          // T-090
    let harness = Harness()
    let reply: Data? = await harness.call { proxy, reply in proxy.test(Data("x".utf8), reply: reply) }
    #expect(decode(ActionResult.self, reply)?.error == "bad request")
    #expect(harness.stub.received.isEmpty)
}

@Test func previewEndsWhenItsClientGoes() async throws {             // T-094
    // The app quits or crashes in photo mode: the N4 goes back to its keys instead of keeping the photo.
    let harness = Harness()
    let framing = LockPhotoConfig(path: "/p.jpg", zoom: 2, offsetX: 0, offsetY: 0.1)
    let body = try JSONEncoder().encode(framing)
    let shown: Bool? = await harness.call { proxy, reply in proxy.showLockPhoto(body) { reply(true) } }
    #expect(shown == true)
    #expect(harness.stub.lockPhotos == [framing])
    let cleared: LockPhotoConfig?? = await harness.call { (_: AgentXPC, reply: @escaping (LockPhotoConfig?) -> Void) in
        harness.stub.heardLockPhoto = reply
        harness.client.invalidate()
    }
    #expect(cleared == .some(nil))
    #expect(harness.stub.lockPhotos == [framing, nil])
}

@Test func refusesAPeerThatDoesNotMatch() async {                    // T-102
    // Anything that isn't our app is refused before any call runs.
    let harness = Harness(peerRequirement: { #"identifier "not.this.process""# })
    let reply: Data? = await harness.call(expectingError: true) { proxy, reply in
        proxy.test(Data("{\"action\":\"key:cmd+q\"}".utf8), reply: reply)
    }
    #expect(reply == nil)
    #expect(harness.stub.received.isEmpty)

    // No requirement can be built (e.g. the agent can't read the app): every connection is refused.
    let closed = Harness(peerRequirement: { nil })
    let none: Data? = await closed.call(expectingError: true) { proxy, reply in proxy.status(reply: reply) }
    #expect(none == nil)
}

@Test func acceptsAPeerThatMatches() async throws {                  // T-103
    // The client here is this test process: a requirement pinned to its own signature lets it in.
    let identifier = try #require(CodeSigning.ownIdentifier())
    let me = try #require(CodeSigning.requirement(peerIdentifier: identifier, teamID: nil,
                                                  peerCDHash: CodeSigning.ownCDHash()))
    let harness = Harness(peerRequirement: { me })
    let status: Data? = await harness.call { proxy, reply in proxy.status(reply: reply) }
    #expect(decode(AgentStatus.self, status) == harness.stub.statusValue)
}

@Test func restartRepliesThenExits() async {                         // T-104
    let harness = Harness()
    let replied: Bool? = await harness.call { proxy, reply in proxy.restart { reply(true) } }
    #expect(replied == true)
    let restarted: Bool? = await harness.call { (_: AgentXPC, reply: @escaping (Bool) -> Void) in
        if harness.stub.restarted { reply(true) } else { harness.stub.heardRestart = { reply(true) } }
    }
    #expect(restarted == true)
}

@Test func liveStripPushedToClients() async {                        // T-105
    let spy = ClientSpy()
    let harness = Harness(exporting: spy)
    let first: Data? = await harness.call { proxy, reply in proxy.status(reply: reply) }   // signs the client up
    #expect(first != nil)
    let asked: Data? = await harness.call { proxy, reply in proxy.liveStrip(reply: reply) }
    #expect(decode(LiveStrip.self, asked) == harness.stub.liveStripValue)
    let pushed: Data? = await harness.call { (_: AgentXPC, reply: @escaping (Data) -> Void) in
        spy.heardStrip = reply
        DispatchQueue.main.async { harness.stub.onLiveStripChange?() }
    }
    #expect(decode(LiveStrip.self, pushed) == harness.stub.liveStripValue)
}

@Test func onlyAConnectionThatAskedForTheStatusHearsPushes() async {   // T-162
    // XPC checks the app's signature on a connection's first message, after the agent has accepted it. Asking for
    // the status is what signs a connection up for pushes, so a peer that will be refused hears none.
    let spy = ClientSpy()
    let harness = Harness(exporting: spy)
    let strays = Tally()
    spy.heardStrip = { _ in strays.add() }
    let asked: Data? = await harness.call { proxy, reply in proxy.liveStrip(reply: reply) }   // accepted, not signed up
    #expect(asked != nil)
    DispatchQueue.main.async { harness.stub.onLiveStripChange?() }      // must reach no one
    let status: Data? = await harness.call { proxy, reply in proxy.status(reply: reply) }     // signs it up
    #expect(status != nil)
    let pushed: Data? = await harness.call { (_: AgentXPC, reply: @escaping (Data) -> Void) in
        spy.heard = reply
        DispatchQueue.main.async { harness.stub.onStatusChange?() }
    }
    #expect(decode(AgentStatus.self, pushed) == harness.stub.statusValue)
    // XPC delivers one connection's messages in the order sent: a strip push sent earlier would be here by now.
    #expect(strays.count == 0)
}

@Test func accessibilityRequestReachesTheAgent() async {            // T-124
    let harness = Harness()
    let granted: Bool? = await harness.call { proxy, reply in proxy.requestAccessibility(reply: reply) }
    #expect(granted == false)
    #expect(harness.stub.accessibilityRequests == 1)
}
