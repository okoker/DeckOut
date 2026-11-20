import Foundation

/// What the config app can ask the background part over XPC. Every `Data` is the JSON of the Codable type named,
/// so the wire format is the same types the rest of DeckCore uses.
@objc public protocol AgentXPC {
    /// Reply: `AgentStatus`. Asking for it is what signs the connection up for pushes (`AgentClientXPC`), so the app
    /// asks it first on every connection.
    func status(reply: @escaping (Data) -> Void)
    /// Re-read the config. Reply: `ReloadResult`.
    func reload(reply: @escaping (Data) -> Void)
    /// `TestRequest` in; reply: `ActionResult`.
    func test(_ request: Data, reply: @escaping (Data) -> Void)
    /// `LockPhotoConfig` to show on the N4, or nil to go back to the layout.
    func showLockPhoto(_ framing: Data?, reply: @escaping () -> Void)
    /// Read the shell environment again. Reply: `EnvironmentStatus`.
    func refreshEnvironment(reply: @escaping (Data) -> Void)
    /// Exit after replying; launchd starts the binary now in the bundle (the app was updated).
    func restart(reply: @escaping () -> Void)
    /// Reply: `LiveStrip`.
    func liveStrip(reply: @escaping (Data) -> Void)
    /// Ask macOS to list the agent under Accessibility; reply: whether it's allowed now.
    func requestAccessibility(reply: @escaping (Bool) -> Void)
}

/// What the background part tells the app without being asked, once the app has asked for the status on that
/// connection.
@objc public protocol AgentClientXPC {
    /// `AgentStatus`, sent on deck connect and remove, after each reload and after each environment read.
    func statusChanged(_ status: Data)
    /// `LiveStrip`, sent once per redraw that gives live strip blocks new images.
    func liveStripChanged(_ strip: Data)
}

/// The XPC listener's delegate and exported object. Each connection must meet the peer requirement (our own app,
/// `CodeSigning.appRequirement`), checked by XPC before any call runs. A connection becomes a client when it asks
/// for the status (a checked call), so a peer that XPC will refuse never hears a push. It keeps each client until its
/// connection is invalidated, and pushes status changes to all of them. Calls hop to the main thread before touching
/// `control`.
public final class AgentService: NSObject, NSXPCListenerDelegate, AgentXPC {
    private let control: AgentControl
    /// Evaluated per connection (the app on disk may have been replaced since the last one). Returning nil refuses
    /// the connection. A nil closure accepts every connection: in-process tests only.
    private let peerRequirement: (() -> String?)?
    private var clients: [NSXPCConnection] = []      // main thread only
    /// The client whose lock photo preview is up; when it goes (the app quits or crashes in photo mode), the N4
    /// goes back to its keys. Main thread only.
    private var previewOwner: NSXPCConnection?

    public init(control: AgentControl, peerRequirement: (() -> String?)?) {
        self.control = control
        self.peerRequirement = peerRequirement
        super.init()
        control.onStatusChange = { [weak self] in self?.pushStatus() }
        control.onLiveStripChange = { [weak self] in self?.pushLiveStrip() }
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        if let peerRequirement {
            guard let requirement = peerRequirement() else {
                print("XPC: refused a connection from pid \(connection.processIdentifier): can't tell which app is ours")
                return false
            }
            connection.setCodeSigningRequirement(requirement)
        }
        connection.exportedInterface = NSXPCInterface(with: AgentXPC.self)
        connection.exportedObject = self
        connection.remoteObjectInterface = NSXPCInterface(with: AgentClientXPC.self)
        connection.invalidationHandler = { [weak self, weak connection] in
            DispatchQueue.main.async {
                guard let self else { return }
                if let owner = self.previewOwner, owner === connection {
                    self.previewOwner = nil
                    self.control.showLockPhoto(nil)
                }
                self.clients.removeAll { $0 === connection }
            }
        }
        connection.resume()
        return true
    }

    // MARK: - AgentXPC

    public func status(reply: @escaping (Data) -> Void) {
        let caller = NSXPCConnection.current()      // only valid here, before the hop to main
        DispatchQueue.main.async { [self] in
            // Signed up in the block that replies, so no change falls between the reply and the first push.
            // Queued on main before its removal: XPC calls the invalidation handler after the connection's messages.
            if let caller, !clients.contains(where: { $0 === caller }) { clients.append(caller) }
            reply(Self.encode(control.status()))
        }
    }

    public func reload(reply: @escaping (Data) -> Void) {
        DispatchQueue.main.async { [control] in control.reload { reply(Self.encode($0)) } }
    }

    public func test(_ request: Data, reply: @escaping (Data) -> Void) {
        guard let decoded = try? JSONDecoder().decode(TestRequest.self, from: request) else {
            print("XPC: a test request that doesn't decode")
            reply(Self.encode(ActionResult(error: "bad request")))
            return
        }
        DispatchQueue.main.async { [control] in control.test(decoded) { reply(Self.encode($0)) } }
    }

    public func showLockPhoto(_ framing: Data?, reply: @escaping () -> Void) {
        let caller = NSXPCConnection.current()      // only valid here, before the hop to main
        var decoded: LockPhotoConfig?
        if let framing {
            guard let value = try? JSONDecoder().decode(LockPhotoConfig.self, from: framing) else {
                print("XPC: a lock photo framing that doesn't decode; ignored")
                reply()
                return
            }
            decoded = value
        }
        DispatchQueue.main.async { [self] in
            control.showLockPhoto(decoded)
            previewOwner = decoded == nil ? nil : caller
            reply()
        }
    }

    public func refreshEnvironment(reply: @escaping (Data) -> Void) {
        DispatchQueue.main.async { [control] in control.refreshEnvironment { reply(Self.encode($0)) } }
    }

    public func restart(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [control] in
            reply()
            control.restart()
        }
    }

    public func requestAccessibility(reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [control] in reply(control.requestAccessibility()) }
    }

    public func liveStrip(reply: @escaping (Data) -> Void) {
        DispatchQueue.main.async { [control] in reply(Self.encode(control.liveStrip())) }
    }

    // MARK: - Private

    /// On the main thread (where `onLiveStripChange` fires). With no app to hear it, nothing is built.
    private func pushLiveStrip() {
        guard !clients.isEmpty else { return }
        let strip = Self.encode(control.liveStrip())
        for client in clients {
            (client.remoteObjectProxyWithErrorHandler { _ in } as? AgentClientXPC)?.liveStripChanged(strip)
        }
    }

    /// On the main thread (where `onStatusChange` fires). With no app to hear it, nothing is built.
    private func pushStatus() {
        guard !clients.isEmpty else { return }
        let status = Self.encode(control.status())
        for client in clients {
            (client.remoteObjectProxyWithErrorHandler { _ in } as? AgentClientXPC)?.statusChanged(status)
        }
    }

    private static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }
}
