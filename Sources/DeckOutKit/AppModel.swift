import AppKit
import Combine
import DeckCore
import Foundation

/// What the window shows.
public enum Screen: Equatable {
    case moveToApplications(String)
    case starting
    case needsApproval
    case agentProblem(String)
    case plugIn
    case pickDeck
    case deck(DeckKind)
}

/// The app's state: where it runs, its agent's registration and the link to it, the config, which deck is on screen
/// and what its drawing shows.
@MainActor
public final class AppModel: ObservableObject {
    public let identity: AppIdentity?
    public let appBuild: String
    @Published public private(set) var locationProblem: String?
    @Published public private(set) var registration: RegistrationState?
    @Published public private(set) var config: AppConfig?
    @Published public private(set) var configProblem: String?
    /// The deck on screen; nil on "Plug in your deck" and "Pick a deck".
    @Published public private(set) var shown: DeckKind?
    @Published public var selection: String?
    /// Upright images of the shown deck's keys and picture blocks, rebuilt when the config changes.
    @Published public private(set) var staticImages: [String: CGImage] = [:]
    /// Upright images of the live strip blocks, rebuilt with each push.
    @Published public private(set) var liveImages: [String: CGImage] = [:]
    public let link: AgentLink?
    private let registrar: AgentRegistrar?
    private var watchers: Set<AnyCancellable> = []

    public nonisolated static let notAnsweringText = "DeckOut's background part isn't answering."

    public init(bundle: Bundle = .main) {
        let identity = AppIdentity(bundleID: bundle.bundleIdentifier)
        self.identity = identity
        appBuild = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
        if let identity {
            link = AgentLink(connect: AgentLink.machService(identity), appBuild: appBuild)
            registrar = AgentRegistrar.forAgent(of: identity)
        } else {
            link = nil
            registrar = nil
        }
        link?.onNotAnswering = { [weak self] in await self?.registerAgain() }
        link?.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &watchers)
        // Every status push follows a reload or a deck coming or going: re-read the config, follow the decks.
        link?.$status.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.readConfig()
            self?.followDecks()
        }.store(in: &watchers)
        link?.$liveStrip.receive(on: DispatchQueue.main).sink { [weak self] strip in
            self?.liveImages = strip.images.compactMapValues { DeckPreview.upright(jpeg: $0) }
        }.store(in: &watchers)
    }

    // MARK: - Screens

    public var screen: Screen {
        Self.screen(locationProblem: locationProblem, registration: registration, linkState: link?.state ?? .connecting,
                    status: link?.status, shown: shown)
    }

    public nonisolated static func screen(locationProblem: String?, registration: RegistrationState?, linkState: AgentLink.State,
                              status: AgentStatus?, shown: DeckKind?) -> Screen {
        if let locationProblem { return .moveToApplications(locationProblem) }
        switch registration {
        case nil: return .starting
        case .needsApproval: return .needsApproval
        case .failed(let message): return .agentProblem(message)
        case .enabled: break
        }
        if linkState == .notAnswering { return .agentProblem(notAnsweringText) }
        guard let status else { return .starting }
        return deckScreen(shown: shown, connected: Set(status.decks.compactMap(DeckKind.init(rawValue:))))
    }

    /// Launch: one deck → it, both → pick, none → plug in. The deck on screen stays while plugged in; unplugged, the
    /// other one shows, else "Plug in your deck".
    public nonisolated static func deckScreen(shown: DeckKind?, connected: Set<DeckKind>) -> Screen {
        if let shown, connected.contains(shown) { return .deck(shown) }
        if shown != nil { return connected.first.map { .deck($0) } ?? .plugIn }
        switch connected.count {
        case 0: return .plugIn
        case 1: return .deck(connected.first!)
        default: return .pickDeck
        }
    }

    public var connectedDecks: Set<DeckKind> {
        Set((link?.status?.decks ?? []).compactMap(DeckKind.init(rawValue:)))
    }

    /// The person picked a deck (toolbar button or "Pick a deck").
    public func show(_ deck: DeckKind) {
        guard connectedDecks.contains(deck), shown != deck else { return }
        shown = deck
        selection = nil
        rebuildStaticImages()
    }

    private func followDecks() {
        if case .deck(let deck) = Self.deckScreen(shown: shown, connected: connectedDecks) {
            if deck != shown {
                shown = deck
                selection = nil
                rebuildStaticImages()
            }
        } else {
            shown = nil
            selection = nil
        }
    }

    // MARK: - Launch and registration

    /// Location check, registration, then the link. Debug builds also take `--unregister` (take the agent out of
    /// launchd and Login Items, then quit), for test sessions.
    public func launch(arguments: [String] = CommandLine.arguments, bundlePath: String = Bundle.main.bundlePath) async {
        guard let identity, let registrar, let link else {
            locationProblem = "Run DeckOut from its app bundle (make app)."
            log("not inside a DeckOut bundle")
            return
        }
        #if DEBUG
        if arguments.contains("--unregister") {
            do {
                try await registrar.unregister()
                log("agent unregistered")
            } catch {
                log("unregister failed: \(error.localizedDescription)")
            }
            exit(0)
        }
        #endif
        if let problem = AppLocation.problem(bundlePath: bundlePath, identity: identity) {
            locationProblem = problem
            log("location: \(problem)")
            return
        }
        readConfig()
        let state = await registrar.ensureRegistered()
        registration = state
        log("registration: \(state)")
        if state == .enabled { link.start() }
    }

    /// After the person comes back from System Settings: try again.
    public func recheckRegistration() async {
        guard let registrar, registration == .needsApproval || isFailed(registration) else { return }
        let state = await registrar.ensureRegistered()
        registration = state
        log("registration recheck: \(state)")
        if state == .enabled { link?.start() }
    }

    public func tryAgain() async {
        await registerAgain()
    }

    private func registerAgain() async {
        guard let registrar else { return }
        let state = await registrar.registerAgain()
        registration = state
        log("registered again: \(state)")
    }

    private func isFailed(_ state: RegistrationState?) -> Bool {
        if case .failed = state { return true }
        return false
    }

    // MARK: - Config and images

    private func readConfig() {
        guard let identity else { return }
        let path = identity.configPath(home: FileManager.default.homeDirectoryForCurrentUser.path)
        switch ConfigFile.load(at: path) {
        case .success(let loaded):
            if loaded != config {
                config = loaded
                rebuildStaticImages()
            }
            configProblem = nil
        case .failure(let error):
            configProblem = error.description
        }
    }

    private func rebuildStaticImages() {
        guard let shown, let config else {
            staticImages = [:]
            return
        }
        var images: [String: CGImage] = [:]
        let keys = shown == .n4 ? config.n4?.keys ?? [:] : config.n3?.buttons ?? [:]
        for (key, button) in keys {
            if let icon = button.icon, let image = DeckPreview.keyImage(path: icon, deck: shown) { images[key] = image }
        }
        if shown == .n4 {
            for (block, settings) in config.n4?.strip ?? [:] where settings.type == .picture {
                if let icon = settings.icon, let image = DeckPreview.stripPicture(path: icon) { images[block] = image }
            }
        }
        staticImages = images
    }

    /// What the drawing shows: keys and pictures, with the live blocks on top.
    public var images: [String: CGImage] {
        guard shown == .n4 else { return staticImages }
        let liveBlocks = Set((config?.n4?.strip ?? [:]).filter { [.internet, .load, .volume].contains($0.value.type) }.keys)
        return staticImages.merging(liveImages.filter { liveBlocks.contains($0.key) }) { _, live in live }
    }

    /// Knob captions for the drawing.
    public var captions: [String: String] {
        guard let shown, let config else { return [:] }
        let knobs = shown == .n4 ? config.n4?.knobs ?? [:] : config.n3?.knobs ?? [:]
        return knobs.mapValues { ActionNames.knobCaption($0) }
    }

    // MARK: - Status line

    public enum Health { case good, busy, problem }

    public var statusLine: (health: Health, text: String) {
        switch screen {
        case .moveToApplications: return (.problem, "Not in Applications")
        case .needsApproval: return (.problem, "Deck controller switched off in Login Items")
        case .agentProblem: return (.problem, "Deck controller not running")
        case .starting: return (.busy, "Starting the deck controller…")
        default: break
        }
        if case .versionMismatch(let agent, let app) = link?.state {
            return (.problem, "Deck controller is build \(agent), the app is \(app): quit and open DeckOut again")
        }
        if let configProblem = link?.status?.configProblem ?? configProblem {
            return (.problem, configProblem)
        }
        if let environment = link?.status?.environment, environment.state == .fellBack {
            return (.busy, "Deck controller running · your shell's settings didn't load (\(environment.detail ?? "unknown"))")
        }
        return (.good, "Deck controller running")
    }

    func log(_ line: String) {
        print("DeckOut: \(line)")
        fflush(stdout)
    }
}
