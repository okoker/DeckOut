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

    /// Switch to a new, already validated config and redraw every connected deck.
    public func reload(_ newConfig: AppConfig) {
        config = newConfig
        dispatcher.shutdown()
        dispatcher = ActionDispatcher(config: newConfig)
        for connection in decks.connections {
            connection.setBrightness(brightness(for: connection.model.kind))
            if connection.model.kind == .n3 { connection.clearAll() }   // N3 reload as in v1.0.0
            drawLayout(connection)
        }
    }

    // MARK: - Decks

    private func connected(_ connection: DeckConnection) {
        connection.start(brightness: brightness(for: connection.model.kind))
        drawLayout(connection)
    }

    private func brightness(for kind: DeckKind) -> Int {
        switch kind {
        case .n3: return config.n3?.brightness ?? 50
        case .n4: return config.n4?.brightness ?? 50
        }
    }

    /// Draws every slot the deck shows, then one commit.
    private func drawLayout(_ connection: DeckConnection) {
        let started = Date()
        let model = connection.model
        var drawn = 0
        switch model.kind {
        case .n3:
            // As in v1.0.0: only keys with an icon are drawn (the deck was cleared first).
            for (key, slot) in model.keySlots.sorted(by: { $0.value < $1.value }) {
                guard let path = config.n3?.buttons[key]?.icon else { continue }
                guard let jpeg = ImageLoader.loadAsJPEG(path: path) else {
                    print("Warning: failed to load icon for \(key): \(path)")
                    continue
                }
                connection.draw(slot: slot, jpeg: jpeg)
                drawn += 1
            }
        case .n4:
            let keyBlank = StripRenderer.blank(w: IconImage.n4Size, h: IconImage.n4Size)
            for (key, slot) in model.keySlots.sorted(by: { $0.value < $1.value }) {
                let jpeg = config.n4?.keys[key]?.icon.flatMap { IconImage.renderN4(path: $0) } ?? keyBlank
                connection.draw(slot: slot, jpeg: jpeg)
                drawn += 1
            }
            for (block, slot) in model.stripSlots.sorted(by: { $0.value < $1.value }) {
                let blockConfig = config.n4?.strip[block]
                var jpeg: Data?
                if blockConfig?.type == .picture, let path = blockConfig?.icon {
                    jpeg = StripRenderer.picture(path: path)
                }
                connection.draw(slot: slot, jpeg: jpeg ?? StripRenderer.blank())
                drawn += 1
            }
        }
        connection.commit()
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        print("Drew \(drawn) slots on \(model.kind.rawValue) in \(ms) ms")
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
