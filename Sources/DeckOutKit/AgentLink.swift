import DeckCore
import Foundation

/// The app's connection to its agent: asks for the status, hears pushes (status, live strip), reconnects when the
/// agent goes away, and makes sure the agent running is the one in this app's bundle.
@MainActor
public final class AgentLink: ObservableObject {
    public enum State: Equatable {
        case connecting
        case connected
        /// The agent doesn't answer (not started, or stuck).
        case notAnswering
        /// Still another build after one restart: the agent running isn't the one in this app.
        case versionMismatch(agent: String, app: String)
    }

    @Published public private(set) var status: AgentStatus?
    @Published public private(set) var liveStrip = LiveStrip(images: [:])
    @Published public private(set) var state: State = .connecting

    /// Runs once, the first time the agent doesn't answer (the app registers the agent again).
    public var onNotAnswering: (() async -> Void)?

    private let connect: () -> NSXPCConnection
    private let appBuild: String
    private let retryDelay: TimeInterval
    private let answerTimeout: TimeInterval
    private var connection: NSXPCConnection?
    private var generation = 0          // handlers of a dropped connection are ignored
    private var restartAsked = false     // at most once per app launch
    private var notAnsweringReported = false
    private lazy var receiver = Receiver(link: self)

    public init(connect: @escaping () -> NSXPCConnection, appBuild: String, retryDelay: TimeInterval = 1,
                answerTimeout: TimeInterval = 10) {
        self.connect = connect
        self.appBuild = appBuild
        self.retryDelay = retryDelay
        self.answerTimeout = answerTimeout
    }

    /// The real connection: DeckOut's Mach service, checked against the agent's signature.
    public nonisolated static func machService(_ identity: AppIdentity) -> () -> NSXPCConnection {
        {
            let connection = NSXPCConnection(machServiceName: identity.agentLabel)
            connection.setCodeSigningRequirement(CodeSigning.agentRequirement(identity: identity))
            return connection
        }
    }

    public func start() {
        open()
    }

    /// One call to the agent; `failure` runs if the connection drops before a reply.
    public func call(_ body: (AgentXPC) -> Void, failure: @escaping @Sendable (Error) -> Void = { _ in }) {
        guard let connection, let proxy = connection.remoteObjectProxyWithErrorHandler(failure) as? AgentXPC else { return }
        body(proxy)
    }

    // MARK: - Connection

    private func open() {
        generation += 1
        let mine = generation
        let connection = connect()
        connection.remoteObjectInterface = NSXPCInterface(with: AgentXPC.self)
        connection.exportedInterface = NSXPCInterface(with: AgentClientXPC.self)
        connection.exportedObject = receiver
        connection.interruptionHandler = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.dropped(mine) } }
        }
        connection.invalidationHandler = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.dropped(mine) } }
        }
        self.connection = connection
        connection.resume()
        askStatus(mine)
    }

    /// The agent went away (it exited, crashed or restarted): start again with a fresh connection.
    private func dropped(_ which: Int) {
        guard which == generation else { return }
        generation += 1                     // ignore the rest of this connection's handlers
        connection?.invalidate()
        connection = nil
        if state == .connected { state = .connecting }
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
            MainActor.assumeIsolated { self?.open() }
        }
    }

    private func askStatus(_ which: Int) {
        var answered = false
        call({ proxy in
            proxy.status { [weak self] data in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        answered = true
                        guard let self, which == self.generation else { return }
                        self.received(status: data)
                        self.askLiveStrip()
                    }
                }
            }
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + answerTimeout) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, which == self.generation, !answered else { return }
                self.state = .notAnswering
                if !self.notAnsweringReported, let hook = self.onNotAnswering {
                    self.notAnsweringReported = true
                    Task { await hook() }
                }
            }
        }
    }

    private func askLiveStrip() {
        call({ proxy in
            proxy.liveStrip { data in
                DispatchQueue.main.async { MainActor.assumeIsolated { [weak self] in self?.received(strip: data) } }
            }
        })
    }

    // MARK: - Replies and pushes

    fileprivate func received(status data: Data) {
        guard let decoded = try? JSONDecoder().decode(AgentStatus.self, from: data) else { return }
        status = decoded
        guard decoded.build == appBuild else {
            if restartAsked {
                state = .versionMismatch(agent: decoded.build ?? "older", app: appBuild)
            } else {
                restartAsked = true
                state = .connecting
                call({ proxy in proxy.restart {} })
            }
            return
        }
        state = .connected
    }

    fileprivate func received(strip data: Data) {
        guard let decoded = try? JSONDecoder().decode(LiveStrip.self, from: data) else { return }
        liveStrip = decoded
    }
}

/// The object the agent calls back. Pushes arrive on an XPC queue; they hop to the main actor.
private final class Receiver: NSObject, AgentClientXPC {
    weak var link: AgentLink?

    init(link: AgentLink) { self.link = link }

    func statusChanged(_ status: Data) {
        DispatchQueue.main.async { MainActor.assumeIsolated { [weak self] in self?.link?.received(status: status) } }
    }

    func liveStripChanged(_ strip: Data) {
        DispatchQueue.main.async { MainActor.assumeIsolated { [weak self] in self?.link?.received(strip: strip) } }
    }
}
