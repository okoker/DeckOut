import Foundation

/// What the background part reports to the config app.
public struct AgentStatus: Codable, Equatable {
    public var version: String
    public var decks: [String]                    // connected decks, "n3" / "n4", sorted
    public var activePresets: [String: String]    // deck → live preset
    public var configProblem: String?             // why the config file didn't load, if it didn't
    public var environment: EnvironmentStatus

    public init(version: String, decks: [String], activePresets: [String: String], configProblem: String?,
                environment: EnvironmentStatus) {
        self.version = version
        self.decks = decks
        self.activePresets = activePresets
        self.configProblem = configProblem
        self.environment = environment
    }
}

/// One action to run as a press would, from the config app's Test button.
public struct TestRequest: Codable, Equatable {
    public var action: String
    public var step: Int?

    public init(action: String, step: Int?) {
        self.action = action
        self.step = step
    }
}

/// What the XPC service asks of the background part. Called on the main thread.
public protocol AgentControl: AnyObject {
    func status() -> AgentStatus
    /// Re-read the config (from the app: no environment refresh).
    func reload(completion: @escaping (ReloadResult) -> Void)
    /// Run one action as a press would, without the lock check.
    func test(_ request: TestRequest, completion: @escaping (ActionResult) -> Void)
    /// Show this lock photo framing on the N4, or nil to go back to the layout.
    func showLockPhoto(_ framing: LockPhotoConfig?)
    func refreshEnvironment(completion: @escaping (EnvironmentStatus) -> Void)
    /// Fires on deck connect and remove, after each reload, and after each environment read.
    var onStatusChange: (() -> Void)? { get set }
}

/// The background part: the config file, the decks, the user's shell environment and reloads.
/// Lives for the whole process; everything runs on the main thread.
public final class Agent: AgentControl {
    public let configPath: String
    private let environment: ShellEnvironment
    private let daemon: Daemon
    private var config: AppConfig
    private var configProblem: String?
    private var environmentRefreshPending = false
    public var onStatusChange: (() -> Void)?

    /// A burst of reload requests (a save per slider step) becomes one reload.
    private lazy var merger = ReloadMerger { [unowned self] in self.reloadNow() }

    public static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

    /// Reads the config. Without a usable one the decks stay blank and the problem is reported: under launchd's
    /// KeepAlive, exiting would restart it into the same failure forever. A reload that loads replaces it.
    public init(configPath: String, environment: ShellEnvironment = .init()) {
        self.configPath = configPath
        self.environment = environment
        let startup = ConfigFile.startupConfig(at: configPath)
        if let problem = startup.problem {
            print(problem)
            print("Starting with no decks set up (they stay blank) until a reload loads a config.")
        } else {
            Self.printConfig(startup.config, path: configPath)
        }
        config = startup.config
        configProblem = startup.problem
        daemon = Daemon(config: startup.config, environment: environment)
    }

    /// Reads the shell environment and opens the decks. `showLockPhoto`: keep the N4's lock photo up
    /// (`--show-lock-photo`).
    public func start(showLockPhoto: Bool) {
        daemon.onDecksChanged = { [weak self] in self?.onStatusChange?() }
        refreshEnvironment { _ in }
        daemon.start()
        if showLockPhoto { daemon.showLockPhoto(config.n4?.lockPhoto) }
    }

    /// A reload from outside (SIGHUP, `--post-reload`): merged with others, then one environment read.
    public func externalReload() {
        environmentRefreshPending = true
        merger.request { [weak self] _ in
            guard let self, self.environmentRefreshPending else { return }
            self.environmentRefreshPending = false
            self.refreshEnvironment { _ in }
        }
    }

    // MARK: - AgentControl

    public func status() -> AgentStatus {
        var presets: [String: String] = [:]
        if let n3 = config.n3 { presets[DeckKind.n3.rawValue] = n3.active.name }
        if let n4 = config.n4 { presets[DeckKind.n4.rawValue] = n4.active.name }
        return AgentStatus(version: Self.version, decks: daemon.connectedKinds.map(\.rawValue).sorted(),
                           activePresets: presets, configProblem: configProblem, environment: environment.status)
    }

    public func reload(completion: @escaping (ReloadResult) -> Void) {
        merger.request(completion)
    }

    public func test(_ request: TestRequest, completion: @escaping (ActionResult) -> Void) {
        daemon.run(action: request.action, step: request.step, completion: completion)
    }

    public func showLockPhoto(_ framing: LockPhotoConfig?) {
        daemon.showLockPhoto(framing)
    }

    public func refreshEnvironment(completion: @escaping (EnvironmentStatus) -> Void) {
        environment.refresh { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                let status = self.environment.status
                print(status.state == .resolved ? "Shell environment: resolved"
                                                : "Shell environment: fell back (\(status.detail ?? "unknown"))")
                completion(status)
                self.onStatusChange?()
            }
        }
    }

    // MARK: - Reload

    /// Re-read the config through the same security checks; on any failure keep the previous one.
    private func reloadNow() -> ReloadResult {
        print("\nReloading config...")
        let result: ReloadResult
        switch ConfigFile.load(at: configPath) {
        case .success(let newConfig):
            Self.printConfig(newConfig, path: configPath)
            config = newConfig
            configProblem = nil
            daemon.reload(newConfig)
            print("Config reloaded.")
            result = ReloadResult(loaded: true, problem: nil)
        case .failure(let error):
            print("\(error.description) — keeping previous config.")
            configProblem = error.description
            result = ReloadResult(loaded: false, problem: error.description)
        }
        onStatusChange?()
        return result
    }

    // MARK: - Load summary

    private static func printConfig(_ config: AppConfig, path: String) {
        print("Config loaded from: \(path)")
        if let n3 = config.n3 {
            print(" N3:")
            printPreset(active: n3.activePreset, live: n3.active.name, count: n3.presets.count)
            print("  Brightness:        \(n3.brightness)")
            printButtons(n3.buttons, label: "Buttons")
            printKnobs(n3.knobs)
        }
        if let n4 = config.n4 {
            print(" N4:")
            printPreset(active: n4.activePreset, live: n4.active.name, count: n4.presets.count)
            print("  Brightness:        \(n4.brightness)")
            printButtons(n4.keys, label: "Keys")
            printKnobs(n4.knobs)
            print("  Strip blocks:      \(n4.strip.count)")
            for (name, block) in n4.strip.sorted(by: { $0.key < $1.key }) {
                let tap = block.action.map { ", tap=\($0)" } ?? ""
                print("    \(name): \(block.type.rawValue)\(tap)")
            }
            print("  Swipe:             \(n4.swipe?.action ?? "none")")
            print("  Lock photo:        \(n4.lockPhoto.map { "\($0.path) (zoom \($0.zoom), offset \($0.offsetX), \($0.offsetY))" } ?? "none")")
        }
        if let displays = config.displays, !displays.isEmpty {
            print("  Displays configured: \(displays.count)")
            for d in displays {
                print("    \(d.name): serial=\(d.serial)")
            }
        }
    }

    /// "Preset: Music (2 presets)", and a warning when `active_preset` names no preset.
    private static func printPreset(active: String, live: String, count: Int) {
        if active != live { print("  Warning: active_preset \"\(active)\" not found, using \"\(live)\"") }
        print("  Preset: \(live) (\(count) preset\(count == 1 ? "" : "s"))")
    }

    private static func printButtons(_ buttons: [String: ButtonConfig], label: String) {
        print("  \(label) configured: \(buttons.count)")
        for (name, btn) in buttons.sorted(by: { $0.key < $1.key }) {
            let iconNote = btn.icon.map { " (icon: \($0))" } ?? ""
            print("    \(name): \(btn.action)\(iconNote)")
        }
    }

    private static func printKnobs(_ knobs: [String: KnobConfig]) {
        print("  Knobs configured:  \(knobs.count)")
        for (name, knob) in knobs.sorted(by: { $0.key < $1.key }) {
            let rotateStep = knob.rotate.step.map { ", step: \($0)" } ?? ""
            print("    \(name): rotate=\(knob.rotate.action)\(rotateStep), press=\(knob.press.action)")
        }
    }
}
