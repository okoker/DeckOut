import DeckCore
import Foundation

/// The app's state: where it runs, its agent's registration and the link to it.
@MainActor
public final class AppModel: ObservableObject {
    public let identity: AppIdentity?
    public let appBuild: String
    @Published public private(set) var locationProblem: String?
    @Published public private(set) var registration: RegistrationState?
    public let link: AgentLink?
    private let registrar: AgentRegistrar?

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
    }

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
        let state = await registrar.ensureRegistered()
        registration = state
        log("registration: \(state)")
        if state == .enabled { link.start() }
    }

    private func registerAgain() async {
        guard let registrar else { return }
        let state = await registrar.registerAgain()
        registration = state
        log("not answering; registered again: \(state)")
    }

    func log(_ line: String) {
        print("DeckOut: \(line)")
        fflush(stdout)
    }
}
