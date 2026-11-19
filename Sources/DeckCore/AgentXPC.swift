import Foundation

/// What the config app can ask the background part over XPC. Every `Data` is the JSON of the Codable type named,
/// so the wire format is the same types the rest of DeckCore uses.
@objc public protocol AgentXPC {
    /// Reply: `AgentStatus`.
    func status(reply: @escaping (Data) -> Void)
    /// Re-read the config. Reply: `ReloadResult`.
    func reload(reply: @escaping (Data) -> Void)
    /// `TestRequest` in; reply: `ActionResult`.
    func test(_ request: Data, reply: @escaping (Data) -> Void)
    /// `LockPhotoConfig` to show on the N4, or nil to go back to the layout.
    func showLockPhoto(_ framing: Data?, reply: @escaping () -> Void)
    /// Read the shell environment again. Reply: `EnvironmentStatus`.
    func refreshEnvironment(reply: @escaping (Data) -> Void)
}

/// What the background part tells the app without being asked.
@objc public protocol AgentClientXPC {
    /// `AgentStatus`, sent on deck connect and remove, after each reload and after each environment read.
    func statusChanged(_ status: Data)
}

/// The XPC listener's delegate and exported object. It accepts every connection (before signing, anything
/// running as the user may connect, and gets nothing it couldn't already do as the user; code-signing checks come
/// with the signed app bundle). It keeps each client until its connection is invalidated, and pushes status
/// changes to all of them. Calls hop to the main thread before touching `control`.
public final class AgentService: NSObject, NSXPCListenerDelegate, AgentXPC {
    private let control: AgentControl
    private var clients: [NSXPCConnection] = []      // main thread only
    /// The client whose lock photo preview is up; when it goes (the app quits or crashes in photo mode), the N4
    /// goes back to its keys. Main thread only.
    private var previewOwner: NSXPCConnection?

    public init(control: AgentControl) {
        self.control = control
        super.init()
        control.onStatusChange = { [weak self] in self?.pushStatus() }
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
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
        DispatchQueue.main.async { self.clients.append(connection) }
        connection.resume()
        return true
    }

    // MARK: - AgentXPC

    public func status(reply: @escaping (Data) -> Void) {
        DispatchQueue.main.async { [control] in reply(Self.encode(control.status())) }
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

    // MARK: - Private

    /// On the main thread (where `onStatusChange` fires).
    private func pushStatus() {
        let status = Self.encode(control.status())
        for client in clients {
            (client.remoteObjectProxyWithErrorHandler { _ in } as? AgentClientXPC)?.statusChanged(status)
        }
    }

    private static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }
}
