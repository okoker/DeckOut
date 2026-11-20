import AppKit
import Combine
import DeckCore
import Foundation

/// What the window shows.
public enum Screen: Equatable {
    case moveToApplications(String)
    /// The hand-installed controller from before DeckOut is there: retire it, or keep it, before registering.
    case oldController
    /// The deck controller was stopped and taken out of Login Items (removal).
    case removed
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
    /// The person's home folder (tests use a temp one).
    let home: String
    @Published public private(set) var oldControllerPending = false
    @Published public private(set) var keptOldController = false
    @Published public private(set) var oldControllerProblem: String?
    @Published public private(set) var retiring = false
    @Published public private(set) var removed = false
    /// Stop and Remove's unregister hasn't run yet (waiting its turn, or macOS hasn't answered): the window says the
    /// controller is stopping and its Quit and Start Again wait, so the agent isn't left registered.
    @Published public private(set) var removing = false
    @Published public private(set) var removalProblem: String?
    /// External monitors as m1ddc lists them now, and where each sits.
    @Published public internal(set) var monitors: [Monitor] = []
    @Published public internal(set) var monitorPlaces: [UInt32: String] = [:]
    @Published public internal(set) var monitorsNote: String?
    @Published public private(set) var locationProblem: String?
    @Published public private(set) var registration: RegistrationState?
    @Published public private(set) var config: AppConfig?
    @Published public private(set) var configProblem: String?
    @Published public private(set) var configNotice: String?
    /// Why the last chosen picture wasn't used.
    @Published public var iconProblem: String?
    /// The icon library (the app's own; tests set the repo's).
    var symbolLibrary: SymbolLibrary? = SymbolLibrary.shared
    /// The window is in lock photo mode (N4): the deck shows the photo; the editor its framing.
    @Published public internal(set) var photoMode = false
    /// While in photo mode, the real N4 shows the photo too.
    @Published public var showOnDeck = true { didSet { if photoMode { sendPreview(force: true) } } }
    /// Draw faintly what falls between the screens.
    @Published public var showHiddenParts = false
    /// Why the last chosen lock photo wasn't used.
    @Published public var photoProblem: String?
    /// The lock photo decoded for the drawing (by path; downscaled like the agent's).
    let photoCache = LockPhoto.PreviewCache()
    /// What the N4 was last told: nil never; `.some(nil)` its keys; `.some(framing)` that photo.
    @Published public internal(set) var deckPreview: LockPhotoConfig??
    var lastPreviewSent = Date.distantPast
    var previewScheduled = false
    /// The deck on screen; nil on "Plug in your deck" and "Pick a deck".
    @Published public internal(set) var shown: DeckKind?
    @Published public var selection: String? { didSet { iconProblem = nil; executableProblem = nil } }
    /// Why Make Executable didn't work, shown under its button until another control is selected.
    @Published public var executableProblem: String?
    /// Edit in Window…'s command window, while it's open.
    @Published public var commandEdit: CommandEdit?
    /// Upright images of the shown deck's keys and picture blocks, rebuilt when the config changes.
    @Published public private(set) var staticImages: [String: CGImage] = [:]
    /// Upright images of the live strip blocks, rebuilt with each push.
    @Published public private(set) var liveImages: [String: CGImage] = [:]
    public let link: AgentLink?
    /// The config the window edits; nil outside a DeckOut bundle.
    public let store: ConfigStore?
    private let registrar: AgentRegistrar?
    private var watchers: Set<AnyCancellable> = []
    /// Apple Shortcuts by name, for "Run a Shortcut" (read with `shortcuts list` when first needed).
    @Published public var shortcutNames: [String]?
    /// The tool that lists them (tests set a stand-in, so they never read the person's own Shortcuts).
    var shortcutsTool = "/usr/bin/shortcuts"
    /// A read of the list is under way (main thread only).
    var readingShortcuts = false

    public nonisolated static let notAnsweringText = "DeckOut's background part isn't answering."

    public convenience init(bundle: Bundle = .main) {
        let identity = AppIdentity(bundleID: bundle.bundleIdentifier)
        let appBuild = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
        guard let identity else {
            self.init(identity: nil, appBuild: appBuild, link: nil, store: nil, registrar: nil)
            return
        }
        let link = AgentLink(connect: AgentLink.machService(identity), appBuild: appBuild)
        let store = ConfigStore(path: identity.configPath(home: FileManager.default.homeDirectoryForCurrentUser.path),
                                reload: { [weak link] in link?.call({ $0.reload { _ in } }) })
        self.init(identity: identity, appBuild: appBuild, link: link, store: store,
                  registrar: AgentRegistrar.forAgent(of: identity))
    }

    /// The parts, given: the app's own (above), or a store alone for previews and tests (no agent).
    init(identity: AppIdentity?, appBuild: String, link: AgentLink?, store: ConfigStore?, registrar: AgentRegistrar?,
         home: String = NSHomeDirectory()) {
        self.identity = identity
        self.appBuild = appBuild
        self.home = home
        self.link = link
        self.store = store
        self.registrar = registrar
        link?.onNotAnswering = { [weak self] in await self?.tryAgain() }   // as Try Again does, in turn
        store?.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &watchers)
        store?.$config.sink { [weak self] config in   // the store publishes on the main actor
            guard let self, config != self.config else { return }
            self.config = config
            self.rebuildStaticImagesIfNeeded()
            // Whatever changed the photo (a move, undo, a hand edit), the N4 shows what the window shows.
            if self.photoMode { self.sendPreview() }
        }.store(in: &watchers)
        link?.$state.sink { [weak self] state in
            // A reconnect drops the agent's preview (it ends with the old connection): put it back.
            guard let self, state == .connected, self.photoMode else { return }
            DispatchQueue.main.async { self.sendPreview(force: true) }
        }.store(in: &watchers)
        store?.$problem.sink { [weak self] in self?.configProblem = $0 }.store(in: &watchers)
        store?.$notice.sink { [weak self] in self?.configNotice = $0 }.store(in: &watchers)
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
        if locationProblem == nil {
            if oldControllerPending { return .oldController }
            if removed { return .removed }
        }
        return Self.screen(locationProblem: locationProblem, registration: registration,
                           linkState: link?.state ?? .connecting, status: link?.status, shown: shown)
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
        if photoMode { leavePhotoMode() }
        shown = deck
        selection = nil
        rebuildStaticImages()
    }

    private func followDecks() {
        followDecks(connected: connectedDecks)
    }

    func followDecks(connected: Set<DeckKind>) {
        if case .deck(let deck) = Self.deckScreen(shown: shown, connected: connected) {
            if deck != shown {
                if photoMode { leavePhotoMode() }
                shown = deck
                selection = nil
                rebuildStaticImages()
            }
        } else {
            if photoMode { leavePhotoMode() }   // tells the agent too: the N4 shows its keys when it's back
            shown = nil
            selection = nil
        }
    }

    // MARK: - Launch and registration

    /// The registration step asked for last. Each step waits for the one before it, so they run one at a time, in
    /// the order they were asked for (BL-010): a re-registration under way finishes before Stop and Remove unregisters.
    private var lastStep: Task<Void, Never>?

    /// Runs `step` once every step asked for before it has run, and returns when it has run too. Only the public
    /// entry points call this. A step never calls an entry point: it would wait for itself, and no registration step
    /// would run again until the app quits.
    private func inTurn(_ step: @escaping @MainActor () async -> Void) async {
        let before = lastStep
        let mine = Task {
            await before?.value
            await step()
        }
        lastStep = mine
        await mine.value
    }

    /// Location check, registration, then the link. Debug builds also take `--unregister` (take the agent out of
    /// launchd and Login Items, then quit), for test sessions.
    public func launch(arguments: [String] = CommandLine.arguments, bundlePath: String = Bundle.main.bundlePath) async {
        guard let identity, let registrar else {
            locationProblem = "Run DeckOut from its app bundle (make app)."
            log("not inside a DeckOut bundle")
            return
        }
        guard !removed else { return }      // removed on purpose: only Start Again brings it back
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
        store?.load()
        // The hand-installed controller first: two controllers would both act on every press. (Debug runs that
        // drive the app themselves skip the question; a release build has no such runs.)
        #if DEBUG
        let automated = (arguments.contains("--selftest") || arguments.contains("--snapshot"))
            && !arguments.contains("--show-old-controller")
        #else
        let automated = false
        #endif
        if !automated, OldController.find(home: home) != nil {
            oldControllerPending = true
            log("found the hand-installed controller; asking before registering")
            return
        }
        await inTurn { await self.register() }
    }

    /// Registers the agent with macOS, then starts the link. Never while removed. A step: only through `inTurn`.
    private func register() async {
        guard let registrar, !removed else { return }
        let state = await registrar.ensureRegistered()
        registration = state
        log("registration: \(state)")
        if state == .enabled { link?.start() }
    }

    /// Retire It: launchd stops the old controller and its plist moves aside (kept); then DeckOut registers.
    public func retireOldController(launchctl: @escaping @Sendable ([String]) -> Int32 = { OldController.runLaunchctl($0) }) async {
        guard !retiring else { return }      // a double click
        retiring = true
        defer { retiring = false }
        let home = self.home
        do {
            try await Task.detached { try OldController.retire(home: home, launchctl: launchctl) }.value
        } catch OldController.RetireError.stillRunning {
            oldControllerProblem = "It's still running: launchd didn't stop it. Log out and back in, then try again."
            return
        } catch {
            oldControllerProblem = "It couldn't be moved aside: \(error.localizedDescription)"
            return
        }
        oldControllerProblem = nil
        oldControllerPending = false
        log("retired the hand-installed controller")
        await inTurn { await self.register() }
    }

    /// Not Now: DeckOut registers its own anyway; the status line keeps saying both are installed.
    public func keepOldController() async {
        oldControllerPending = false
        keptOldController = true
        await inTurn { await self.register() }
    }

    /// Stops the deck controller and takes it out of Login Items (the first step of removing DeckOut). Removed is set
    /// first and the link stopped, so the window says so at once and nothing (the not-answering recovery, coming back
    /// to the app, the window opening again) registers it again; only Start Again does. The unregister waits its
    /// turn: a step under way finishes first, then the link is stopped again (that step may have started it) and the
    /// agent unregistered, last. Until that has run, `removing` keeps the window saying it's stopping. Asked for
    /// again while removed, it does nothing (Start Again clears removed, so a later removal works).
    public func stopAndRemove() async {
        guard let registrar else { return }
        guard !removed else { return }      // a removal already asked for
        removed = true
        removing = true
        link?.stop()
        await inTurn {
            self.link?.stop()
            do {
                try await registrar.unregister()
                self.removalProblem = nil
                self.log("agent unregistered (removal)")
            } catch {
                // Start Again pressed meanwhile: the person no longer wants the removal.
                if self.removed {
                    self.removalProblem = "macOS didn't take it out of Login Items: \(error.localizedDescription)"
                }
                self.log("unregister failed: \(error.localizedDescription)")
            }
            self.removing = false
        }
    }

    public func startAgain() async {
        removed = false
        removalProblem = nil
        await inTurn { await self.register() }
    }

    /// The app became active (back from System Settings, say): if the agent isn't registered and answering, look
    /// again. Switched off in Login Items while the window was open shows up here as needing approval. A step: only
    /// through `inTurn`.
    private func recheckRegistration() async {
        guard let registrar, registration != nil, !removed, !oldControllerPending, link?.state != .connected else { return }
        let state = await registrar.ensureRegistered()
        let was = registration
        registration = state
        log("registration recheck: \(state)")
        if state == .enabled, was != .enabled { link?.start() }
    }

    /// Try Again, and the link's not-answering hook: take the agent out and register it afresh.
    public func tryAgain() async {
        await inTurn { await self.registerAgain() }
    }

    /// A step: only through `inTurn`.
    private func registerAgain() async {
        guard let registrar, !removed else { return }
        let state = await registrar.registerAgain()
        registration = state
        log("registered again: \(state)")
        if state == .enabled { link?.reconnect() }
    }

    private func isFailed(_ state: RegistrationState?) -> Bool {
        if case .failed = state { return true }
        return false
    }

    // MARK: - Config and images

    /// Picks up the file if it changed on disk (a hand edit, then a reload).
    private func readConfig() {
        store?.externalChange()
    }

    /// How many times the key images were made (tests: a slider drag mustn't remake them).
    private(set) var staticImageBuilds = 0
    /// What the key images were last made from: deck and control → icon file.
    private var staticImageInputs: (deck: DeckKind?, icons: [String: String])?

    /// The icon files the shown deck's drawing uses, by control.
    private func imageInputs() -> [String: String] {
        guard let shown, let config else { return [:] }
        var icons = (shown == .n4 ? config.n4?.keys : config.n3?.buttons)?.compactMapValues(\.icon) ?? [:]
        if shown == .n4 {
            for (block, settings) in config.n4?.strip ?? [:] where settings.type == .picture {
                icons[block] = settings.icon
            }
        }
        return icons
    }

    /// Remakes the key images only when an icon (or the deck) changed: a brightness drag or an action change
    /// doesn't decode every icon again.
    private func rebuildStaticImagesIfNeeded() {
        let inputs = imageInputs()
        if let last = staticImageInputs, last.deck == shown, last.icons == inputs { return }
        rebuildStaticImages()
    }

    func rebuildStaticImages() {
        staticImageBuilds += 1
        staticImageInputs = (shown, imageInputs())
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

    public enum Health: Sendable { case good, busy, problem }

    public var statusLine: (health: Health, text: String) {
        let line = Self.statusLine(screen: screen, linkState: link?.state ?? .connecting, status: link?.status,
                                   configProblem: configProblem)
        if line.health != .problem, keptOldController {
            return (.busy, "An older deck controller is also installed: presses may fire twice")
        }
        if line.health == .good, let configNotice { return (.good, configNotice) }
        return line
    }

    /// The app came to the front: pick up a hand edit made meanwhile, and look at the registration if the link is
    /// down.
    public func becameActive() async {
        store?.externalChange()
        if shortcutNames != nil { loadShortcutNames() }   // only once a picker has needed the list
        await inTurn { await self.recheckRegistration() }
    }

    public nonisolated static func statusLine(screen: Screen, linkState: AgentLink.State, status: AgentStatus?,
                                              configProblem: String?) -> (health: Health, text: String) {
        switch screen {
        case .moveToApplications: return (.problem, "Not in Applications")
        case .oldController: return (.busy, "Waiting: another deck controller is installed")
        case .removed: return (.problem, "Deck controller stopped and out of Login Items")
        case .needsApproval: return (.problem, "Deck controller switched off in Login Items")
        case .agentProblem: return (.problem, "Deck controller not running")
        case .starting: return (.busy, "Starting the deck controller…")
        default: break
        }
        if linkState == .connecting { return (.busy, "Reconnecting to the deck controller…") }
        if case .versionMismatch(let agent, let app) = linkState {
            return (.problem, "Deck controller is build \(agent), the app is \(app): quit and open DeckOut again")
        }
        if let configProblem = status?.configProblem ?? configProblem {
            return (.problem, configProblem)
        }
        if let environment = status?.environment, environment.state == .fellBack {
            return (.busy, "Deck controller running · your shell's settings didn't load (\(environment.detail ?? "unknown"))")
        }
        return (.good, "Deck controller running")
    }

    func log(_ line: String) {
        print("DeckOut: \(line)")
        fflush(stdout)
    }
}
