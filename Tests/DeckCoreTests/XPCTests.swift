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
}

private final class ClientSpy: NSObject, AgentClientXPC, @unchecked Sendable {
    var heard: ((Data) -> Void)?
    func statusChanged(_ status: Data) { heard?(status) }
}

/// One listener + client pair. Keep it alive for the length of the test.
private final class Harness: @unchecked Sendable {
    let stub = StubControl()
    let service: AgentService
    let listener = NSXPCListener.anonymous()
    let client: NSXPCConnection

    init(exporting spy: ClientSpy? = nil) {
        service = AgentService(control: stub)
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

    /// Makes one call and waits for its reply; nil if the connection failed or nothing came within 2 s.
    func call<T>(_ body: @escaping (AgentXPC, @escaping (T) -> Void) -> Void) async -> T? {
        await withCheckedContinuation { (done: CheckedContinuation<T?, Never>) in
            let once = Once(done)
            let proxy = client.remoteObjectProxyWithErrorHandler { error in
                Issue.record("XPC error: \(error)")
                once.resume(nil)
            } as! AgentXPC
            body(proxy) { once.resume($0) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { once.resume(nil) }
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
    let first: Data? = await harness.call { proxy, reply in proxy.status(reply: reply) }   // connects the client
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
