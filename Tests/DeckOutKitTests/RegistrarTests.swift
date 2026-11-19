import Foundation
import ServiceManagement
import Testing
@testable import DeckOutKit

// Registering the agent with macOS, against a fake SMAppService. The status sequences follow what Karabiner-Elements
// handles (src/apps/share/swift/ServiceManagementHelper.swift:35-99 @b237a07).

private final class FakeService: ServiceManaging, @unchecked Sendable {
    var statuses: [SMAppService.Status]     // one per read; the last repeats
    var registerError: Error?
    var registers = 0
    var unregisters = 0

    init(_ statuses: [SMAppService.Status]) { self.statuses = statuses }

    var status: SMAppService.Status { statuses.count > 1 ? statuses.removeFirst() : statuses[0] }
    func register() throws {
        registers += 1
        if let registerError { throw registerError }
    }
    func unregister() async throws { unregisters += 1 }
}

private struct Refused: LocalizedError { var errorDescription: String? { "Operation not permitted" } }

@Test func registersWhenNotRegistered() async {   // T-108
    let fake = FakeService([.notRegistered, .enabled])
    let state = await AgentRegistrar(service: fake, sleep: { _ in }).ensureRegistered()
    #expect(state == .enabled)
    #expect(fake.registers == 1)
    #expect(fake.unregisters == 0)

    // Already enabled: nothing to do.
    let enabled = FakeService([.enabled])
    #expect(await AgentRegistrar(service: enabled, sleep: { _ in }).ensureRegistered() == .enabled)
    #expect(enabled.registers == 0)

    // Enabled but not answering: take it out and register it afresh. Seen 19/11/2026: a replaced ad hoc agent hit
    // a launch constraint violation on its first start, launchd dropped the job and then couldn't find its
    // program; unregister + register brought it back.
    let again = FakeService([.notRegistered, .enabled])
    #expect(await AgentRegistrar(service: again, sleep: { _ in }).registerAgain() == .enabled)
    #expect(again.unregisters == 1)
    #expect(again.registers == 1)
}

@Test func notFoundUnregistersThenRetries() async {   // T-109
    // After `sfltool resetbtm` macOS reports notFound until the job is unregistered and registered again, and a
    // just-installed app can read notFound for a few seconds.
    let fake = FakeService([.notFound, .notFound, .notFound, .enabled])
    var slept = 0
    let state = await AgentRegistrar(service: fake, sleep: { _ in slept += 1 }).ensureRegistered()
    #expect(state == .enabled)
    #expect(fake.unregisters == 1)
    #expect(slept >= 2)

    let never = FakeService([.notFound])
    let failed = await AgentRegistrar(service: never, sleep: { _ in }).ensureRegistered()
    guard case .failed = failed else { Issue.record("expected .failed, got \(failed)"); return }
    #expect(never.registers <= 10)
    #expect(never.unregisters == 1)
}

@Test func requiresApprovalIsReported() async {   // T-110
    let fake = FakeService([.requiresApproval])
    #expect(await AgentRegistrar(service: fake, sleep: { _ in }).ensureRegistered() == .needsApproval)

    // register() refused because Login Items has DeckOut switched off: that's approval, not a failure.
    let refused = FakeService([.notRegistered, .requiresApproval])
    refused.registerError = Refused()
    #expect(await AgentRegistrar(service: refused, sleep: { _ in }).ensureRegistered() == .needsApproval)

    // Refused for another reason: the message is passed on.
    let broken = FakeService([.notRegistered])
    broken.registerError = Refused()
    #expect(await AgentRegistrar(service: broken, sleep: { _ in }).ensureRegistered() == .failed("Operation not permitted"))
}
