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

    // Live strip blocks: each source runs only while a connected deck shows its block.
    private let volumeWatcher = VolumeWatcher()
    private var volumeReading: (percent: Int?, muted: Bool)?
    private var loadActive = false
    private var cpuTicks: CPUTicks?
    private var loadReading: LoadReading?

    private struct LoadReading: Equatable {
        let cpu: Int?
        let mem: Int?
        let memLevel: PressureLevel?
    }

    public init(config: AppConfig) {
        self.config = config
        self.dispatcher = ActionDispatcher(config: config)
    }

    public func start() {
        decks.onConnect = { [weak self] connection in self?.connected(connection) }
        decks.onRemove = { [weak self] _ in self?.updateLiveSources() }
        decks.onInput = { [weak self] kind, input in self?.handle(kind, input) }
        volumeWatcher.onChange = { [weak self] percent, muted in
            print("Volume: \(percent.map { "\($0)%" } ?? "–")\(muted ? ", muted" : "")")
            self?.volumeReading = (percent, muted)
            self?.redrawLive(.volume)
        }
        decks.start()
        keepaliveTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.tick()
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
        updateLiveSources()
    }

    /// Every 5 s: keepalive to every deck, then the periodic live-block readings.
    private func tick() {
        decks.connections.forEach { $0.keepalive() }
        if loadActive { sampleLoad() }
    }

    // MARK: - Decks

    private func connected(_ connection: DeckConnection) {
        connection.start(brightness: brightness(for: connection.model.kind))
        drawAll(connection)
        updateLiveSources()
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
            var jpeg: Data?
            if case .strip(let type) = content { jpeg = liveImage(type) }
            connection.draw(slot: slot, jpeg: jpeg ?? LayoutPlan.render(content, slot: slot, model: model))
        }
        connection.commit()
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        print("Drew \(plan.count) slots on \(model.kind.rawValue) in \(ms) ms")
    }

    // MARK: - Live strip blocks

    /// Live block types shown on any connected deck.
    private func liveTypesShown() -> Set<StripBlockType> {
        var shown = Set<StripBlockType>()
        for connection in decks.connections {
            for case .strip(let type) in LayoutPlan.slots(model: connection.model, config: config).values {
                shown.insert(type)
            }
        }
        return shown
    }

    /// Runs the measurements something on screen needs and stops the rest.
    private func updateLiveSources() {
        let shown = liveTypesShown()
        if shown.contains(.volume) {
            volumeWatcher.start()
        } else {
            volumeWatcher.stop()
            volumeReading = nil
        }

        if shown.contains(.load), !loadActive {
            loadActive = true
            cpuTicks = SystemLoad.readTicks()
            loadReading = nil
            // First CPU figure after 1 s rather than at the next 5 s tick.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, self.loadActive else { return }
                self.sampleLoad()
                if let r = self.loadReading {
                    print("Load block running: CPU \(r.cpu.map(String.init) ?? "–")%, memory \(r.mem.map(String.init) ?? "–")% (\(r.memLevel.map { "\($0)" } ?? "–"))")
                }
            }
        } else if !shown.contains(.load), loadActive {
            loadActive = false
            cpuTicks = nil
            loadReading = nil
        }
    }

    /// One load reading; redraws the load blocks only when a figure changed.
    private func sampleLoad() {
        let ticks = SystemLoad.readTicks()
        var cpu: Int?
        if let previous = cpuTicks, let ticks { cpu = SystemLoad.cpuPercent(prev: previous, cur: ticks) }
        cpuTicks = ticks
        let reading = LoadReading(cpu: cpu, mem: SystemLoad.memoryPercent(), memLevel: SystemLoad.pressureLevel())
        guard reading != loadReading else { return }
        loadReading = reading
        redrawLive(.load)
    }

    /// The image for a live block from its latest reading; nil until that block type is built.
    private func liveImage(_ type: StripBlockType) -> Data? {
        switch type {
        case .volume:
            let reading = volumeReading ?? VolumeControl.current().map { (percent: Optional($0.percent), muted: $0.muted) }
            return StripRenderer.volume(percent: reading?.percent, muted: reading?.muted ?? false)
        case .load:
            let r = loadReading ?? LoadReading(cpu: nil, mem: SystemLoad.memoryPercent(), memLevel: SystemLoad.pressureLevel())
            return StripRenderer.load(cpu: r.cpu, mem: r.mem, memLevel: r.memLevel)
        case .internet, .picture, .empty:
            return nil
        }
    }

    /// Redraws only the slots showing `type`, on every deck that shows it.
    private func redrawLive(_ type: StripBlockType) {
        guard let jpeg = liveImage(type) else { return }
        for connection in decks.connections {
            let slots = LayoutPlan.slots(model: connection.model, config: config)
                .filter { $0.value == .strip(type) }.keys.sorted()
            guard !slots.isEmpty else { continue }
            for slot in slots { connection.draw(slot: slot, jpeg: jpeg) }
            connection.commit()
        }
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
