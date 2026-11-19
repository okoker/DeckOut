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
    private let dropGrace: TimeInterval
    private var connection: NSXPCConnection?
    private var started = false
    private var generation = 0          // handlers of a dropped connection are ignored
    private var restartAsked = false     // at most once per app launch
    private var notAnsweringReported = false
    /// Waiting for the agent to answer, since the link started or last dropped. One deadline for the link, not one
    /// per connection: a connection refused at once never times out on its own, and each retry would restart it.
    private var awaitingAnswer = false
    private var deadline = 0
    /// The wait before the next retry: doubles after each drop without an answer, up to 30 s.
    private var nextRetry: TimeInterval
    private static let longestRetry: TimeInterval = 30
    private lazy var receiver = Receiver(link: self)

    /// `dropGrace`: how long a dropped link keeps showing the last status (an agent restart takes a moment).
    public init(connect: @escaping () -> NSXPCConnection, appBuild: String, retryDelay: TimeInterval = 1,
                answerTimeout: TimeInterval = 10, dropGrace: TimeInterval = 3) {
        self.connect = connect
        self.appBuild = appBuild
        self.retryDelay = retryDelay
        self.answerTimeout = answerTimeout
        self.dropGrace = dropGrace
        nextRetry = retryDelay
    }

    /// The real connection: DeckOut's Mach service, checked against the agent's signature.
    public nonisolated static func machService(_ identity: AppIdentity) -> () -> NSXPCConnection {
        {
            let connection = NSXPCConnection(machServiceName: identity.agentLabel)
            connection.setCodeSigningRequirement(CodeSigning.agentRequirement(identity: identity))
            return connection
        }
    }

    /// Starts the link; once started, starts it over on a new connection.
    public func start() {
        guard !started else {
            reconnect()
            return
        }
        started = true
        armDeadline()
        open()
    }

    /// Start over on a new connection (after the agent was registered afresh), without waiting.
    public func reconnect() {
        nextRetry = retryDelay
        armDeadline()
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
        self.connection?.invalidate()       // its handlers carry an older generation and are ignored
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

    /// The agent went away (it exited, crashed, restarted or refused us): try again after a wait that grows while
    /// nothing answers. After a short grace the old status is dropped, so the window stops showing it as running.
    private func dropped(_ which: Int) {
        guard which == generation else { return }
        generation += 1                     // ignore the rest of this connection's handlers
        let retryAt = generation
        connection?.invalidate()
        connection = nil
        if state == .connected { state = .connecting }
        armDeadline()
        let wait = nextRetry
        nextRetry = min(nextRetry * 2, Self.longestRetry)
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == retryAt else { return }   // reconnected meanwhile
                self.open()
            }
        }
        let graceFor = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + dropGrace) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.awaitingAnswer, self.deadline == graceFor else { return }
                self.status = nil
                self.liveStrip = LiveStrip(images: [:])
            }
        }
    }

    /// From now, the agent has `answerTimeout` to answer; already waiting: the earlier deadline stands.
    private func armDeadline() {
        guard !awaitingAnswer else { return }
        awaitingAnswer = true
        deadline += 1
        let mine = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + answerTimeout) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.awaitingAnswer, self.deadline == mine else { return }
                self.state = .notAnswering
                if !self.notAnsweringReported, let hook = self.onNotAnswering {
                    self.notAnsweringReported = true
                    Task { await hook() }
                }
            }
        }
    }

    private func askStatus(_ which: Int) {
        call({ proxy in
            proxy.status { [weak self] data in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, which == self.generation else { return }
                        self.received(status: data)
                        self.askLiveStrip()
                    }
                }
            }
        })
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
        awaitingAnswer = false
        nextRetry = retryDelay
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
