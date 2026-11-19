import DeckCore
import Testing
@testable import DeckOutKit

@Test func screenFollowsTheDecks() {   // T-118
    let none: Set<DeckKind> = [], both: Set<DeckKind> = [.n3, .n4]
    // Nothing shown yet (launch, or "Plug in your deck"): none → plug in, one → open it, both → pick.
    #expect(AppModel.deckScreen(shown: nil, connected: none) == .plugIn)
    #expect(AppModel.deckScreen(shown: nil, connected: [.n4]) == .deck(.n4))
    #expect(AppModel.deckScreen(shown: nil, connected: [.n3]) == .deck(.n3))
    #expect(AppModel.deckScreen(shown: nil, connected: both) == .pickDeck)
    // A deck on screen stays while it's plugged in, also when the other one arrives.
    #expect(AppModel.deckScreen(shown: .n4, connected: [.n4]) == .deck(.n4))
    #expect(AppModel.deckScreen(shown: .n4, connected: both) == .deck(.n4))
    // The deck on screen is unplugged: the other one, else plug in. Never a deck that isn't there.
    #expect(AppModel.deckScreen(shown: .n4, connected: [.n3]) == .deck(.n3))
    #expect(AppModel.deckScreen(shown: .n3, connected: none) == .plugIn)
}

@Test func screenBeforeTheDecks() {   // T-118
    let ok = AgentStatus(version: "2", build: "b", decks: ["n4"], activePresets: [:], configProblem: nil,
                         environment: EnvironmentStatus(state: .resolved, detail: nil))
    func screen(location: String? = nil, registration: RegistrationState? = .enabled,
                link: AgentLink.State = .connected, status: AgentStatus? = ok) -> Screen {
        AppModel.screen(locationProblem: location, registration: registration, linkState: link, status: status, shown: nil)
    }
    #expect(screen(location: "Move it") == .moveToApplications("Move it"))
    #expect(screen(registration: nil) == .starting)
    #expect(screen(registration: .needsApproval) == .needsApproval)
    #expect(screen(registration: .failed("boom")) == .agentProblem("boom"))
    #expect(screen(link: .notAnswering) == .agentProblem(AppModel.notAnsweringText))
    #expect(screen(link: .connecting, status: nil) == .starting)
    #expect(screen() == .deck(.n4))
    // Another build still running after one restart: the decks still show; the status line says so.
    #expect(screen(link: .versionMismatch(agent: "a", app: "b")) == .deck(.n4))
}
