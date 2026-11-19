import Foundation

/// Drives every connected deck: start-up, layout, keepalive, and inputs → actions.
/// Lives for the whole process; everything runs on the main thread.
public final class Daemon {
    /// Posted (e.g. by `StreamDeckController --post-reload`, later by the config app) to re-read the config.
    public static let reloadNotification = "com.streamdeck.controller.reload"

    private var config: AppConfig
    private var dispatcher: ActionDispatcher
    private let decks = DeckManager()
    private var keepaliveTimer: Timer?

    public init(config: AppConfig) {
        self.config = config
        self.dispatcher = ActionDispatcher(config: config)
    }

    public func start() {
        decks.onConnect = { [weak self] connection in self?.connected(connection) }
        decks.onInput = { [weak self] kind, input in self?.handle(kind, input) }
        decks.start()
        keepaliveTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.decks.connections.forEach { $0.keepalive() }
        }
    }

    /// Switch to a new, already validated config and redraw every connected deck in place.
    public func reload(_ newConfig: AppConfig) {
        config = newConfig
        dispatcher.shutdown()
        dispatcher = ActionDispatcher(config: newConfig)
        for connection in decks.connections {
            connection.setBrightness(brightness(for: connection.model.kind))
            drawAll(connection)
        }
    }

    // MARK: - Decks

    private func connected(_ connection: DeckConnection) {
        connection.start(brightness: brightness(for: connection.model.kind))
        drawAll(connection)
    }

    private func brightness(for kind: DeckKind) -> Int {
        switch kind {
        case .n3: return config.n3?.brightness ?? 50
        case .n4: return config.n4?.brightness ?? 50
        }
    }

    /// Draws every slot of the deck's layout plan in place (a black image where nothing is set),
    /// then one commit. No clear, unless the model needs one.
    func drawAll(_ connection: DeckConnection) {
        let started = Date()
        let model = connection.model
        let plan = LayoutPlan.slots(model: model, config: config)
        if model.clearsBeforeRedraw { connection.clearAll() }
        for (slot, content) in plan.sorted(by: { $0.key < $1.key }) {
            connection.draw(slot: slot, jpeg: LayoutPlan.render(content, slot: slot, model: model))
        }
        connection.commit()
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        print("Drew \(plan.count) slots on \(model.kind.rawValue) in \(ms) ms")
    }

    // MARK: - Input

    private func handle(_ kind: DeckKind, _ input: DeckInput) {
        guard let resolved = ActionResolver.resolve(input, deck: kind, config: config) else {
            switch input {
            case .keyUp, .knobUp: break
            default: print("Input \(kind.rawValue) \(input) → nothing")
            }
            return
        }
        let step = resolved.step.map { " step \($0)" } ?? ""
        print("Input \(kind.rawValue) \(input) → \(resolved.action)\(step)")
        dispatcher.execute(resolved)
    }
}
