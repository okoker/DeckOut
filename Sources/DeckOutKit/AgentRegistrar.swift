import DeckCore
import Foundation
import ServiceManagement

/// What the registrar needs from `SMAppService`; a fake stands in for it in tests.
public protocol ServiceManaging: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() async throws
}

extension SMAppService: ServiceManaging {}

public enum RegistrationState: Equatable {
    case enabled
    /// Switched off in System Settings → General → Login Items & Extensions: the person has to allow it.
    case needsApproval
    case failed(String)
}

/// Registers DeckOut's agent with macOS (`SMAppService.agent`), the way Karabiner-Elements learned to
/// (`src/apps/share/swift/ServiceManagementHelper.swift:35-99` @b237a07): `.notFound` → unregister once, then
/// register, retrying while macOS catches up with a newly installed app (up to 10 tries, 1 s apart).
public final class AgentRegistrar {
    private let service: ServiceManaging
    private let sleep: (TimeInterval) async -> Void

    public init(service: ServiceManaging,
                sleep: @escaping (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1e9)) }) {
        self.service = service
        self.sleep = sleep
    }

    public static func forAgent(of identity: AppIdentity) -> AgentRegistrar {
        AgentRegistrar(service: SMAppService.agent(plistName: identity.agentPlistName))
    }

    public func ensureRegistered() async -> RegistrationState {
        var unregistered = false
        var lastProblem = "macOS doesn't find DeckOut's background part in the app"
        for _ in 0..<10 {
            switch service.status {
            case .enabled:
                return .enabled
            case .requiresApproval:
                return .needsApproval
            case .notRegistered:
                do {
                    try service.register()
                } catch {
                    return service.status == .requiresApproval ? .needsApproval : .failed(error.localizedDescription)
                }
            case .notFound:
                if !unregistered {
                    unregistered = true
                    try? await service.unregister()
                }
                do { try service.register() } catch { lastProblem = error.localizedDescription }
                await sleep(1)
            @unknown default:
                return .failed("macOS reports an unknown state for DeckOut's background part")
            }
        }
        return .failed(lastProblem)
    }

    /// Registered but not answering: take the job out and register it afresh. macOS doesn't always start an
    /// approved job (`src/apps/SettingsWindow/src/ServicesRegister.swift:35-43` @b237a07), and on 19/11/2026 a
    /// replaced ad hoc agent hit a launch constraint violation on its first start, after which launchd couldn't find
    /// its program; unregister + register brought it back.
    public func registerAgain() async -> RegistrationState {
        try? await service.unregister()
        return await ensureRegistered()
    }

    /// Takes the agent out of launchd and Login Items; the decks stop until it is registered again.
    public func unregister() async throws {
        try await service.unregister()
    }
}
