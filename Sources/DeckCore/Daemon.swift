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
    private let lockMonitor = LockMonitor()

    /// Development (`--show-lock-photo`): keep the N4's lock photo up while unlocked, e.g. to line up
    /// the panel rectangles. Keys and knobs work as usual; live readings pause.
    public var showLockPhotoAlways = false

    /// Live readings pause while the lock photo or the locked layout is up.
    private var livePaused: Bool { lockMonitor.locked || showLockPhotoAlways }

    // Live strip blocks: each source runs only while a connected deck shows its block.
    private let volumeWatcher = VolumeWatcher()
    private var volumeReading: (percent: Int?, muted: Bool)?
    private var loadActive = false
    private var cpuTicks: CPUTicks?
    private var loadReading: LoadReading?

    private var latencyProbe: LatencyProbe?
    private var latencyInFlightSince: Date?
    private var latencyPrevious: Double?
    private var internetReading: InternetReading?

    private struct InternetReading: Equatable {
        let ms: Double?
        let trend: Trend
        let failed: Bool
        /// What the block shows; two readings that look the same don't redraw.
        var shown: String { failed ? "failed" : "\(ms.map(StripRenderer.latencyFigure) ?? "–") \(trend)" }
    }

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
        lockMonitor.onChange = { [weak self] locked in self?.lockChanged(locked) }
        lockMonitor.start()
        print("Screen \(lockMonitor.locked ? "locked" : "unlocked") at start")
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
            showCurrent(connection)
        }
        updateLiveSources()
    }

    /// Every 5 s: keepalive to every deck, the lock re-check, then the periodic live-block readings.
    private func tick() {
        decks.connections.forEach { $0.keepalive() }
        lockMonitor.recheck()
        if loadActive { sampleLoad() }
        if latencyProbe != nil { measureLatency() }
    }

    // MARK: - Decks

    private func connected(_ connection: DeckConnection) {
        connection.start(brightness: brightness(for: connection.model.kind))
        showCurrent(connection)
        updateLiveSources()
    }

    /// The layout, or — while the Mac is locked — the N4's lock photo if one is set.
    private func showCurrent(_ connection: DeckConnection) {
        if livePaused, drawLockPhoto(connection) { return }
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
            var jpeg: Data?
            if case .strip(let type) = content { jpeg = liveImage(type) }
            connection.draw(slot: slot, jpeg: jpeg ?? LayoutPlan.render(content, slot: slot, model: model))
        }
        connection.commit()
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        print("Drew \(plan.count) slots on \(model.kind.rawValue) in \(ms) ms")
    }

    // MARK: - Lock

    /// Locked: live readings pause and the N4 shows its lock photo (without one, every deck keeps its
    /// layout, inert). Unlocked: every deck redraws its layout and live readings resume.
    private func lockChanged(_ locked: Bool) {
        print(locked ? "Screen locked" : "Screen unlocked")
        updateLiveSources()
        for connection in decks.connections {
            if locked {
                _ = drawLockPhoto(connection)
            } else {
                showCurrent(connection)
            }
        }
    }

    /// Draws the lock photo across an N4's keys and strip. False (nothing drawn) for another deck,
    /// with no `lock_photo` set, or when the photo can't be read.
    @discardableResult
    private func drawLockPhoto(_ connection: DeckConnection) -> Bool {
        guard connection.model.kind == .n4, let path = config.n4?.lockPhoto else { return false }
        let started = Date()
        let slices = LockPhoto.jpegSlices(path: path)
        guard !slices.isEmpty else { return false }
        for (slot, jpeg) in slices.sorted(by: { $0.key < $1.key }) {
            connection.draw(slot: slot, jpeg: jpeg)
        }
        connection.commit()
        print("Drew lock photo on n4 (\(slices.count) slots) in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
        return true
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
        let shown = livePaused ? [] : liveTypesShown()
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

        if shown.contains(.internet), let block = internetBlock() {
            if latencyProbe?.host != block.host || latencyProbe?.timeout != block.timeoutS {
                latencyProbe = LatencyProbe(host: block.host, timeout: block.timeoutS)
                latencyInFlightSince = nil
                latencyPrevious = nil
                internetReading = nil
                measureLatency()
            }
        } else if latencyProbe != nil {
            latencyProbe = nil
            latencyInFlightSince = nil
            latencyPrevious = nil
            internetReading = nil
        }
    }

    /// The settings of the (first) internet block; every internet block shows the same reading.
    private func internetBlock() -> StripBlockConfig? {
        config.n4?.strip.sorted(by: { $0.key < $1.key }).first(where: { $0.value.type == .internet })?.value
    }

    /// Starts one latency reading, unless one is still running. A lookup can hang far past the echo
    /// timeout when DNS is down: then the block turns red now instead of waiting for it.
    private func measureLatency() {
        guard let probe = latencyProbe else { return }
        if let since = latencyInFlightSince {
            if Date().timeIntervalSince(since) > probe.timeout { showLatency(nil, stillRunning: true) }
            return
        }
        latencyInFlightSince = Date()
        probe.measure { [weak self] ms in
            guard let self, self.latencyProbe === probe else { return }   // probe replaced or stopped
            self.latencyInFlightSince = nil
            self.showLatency(ms)
        }
    }

    private func showLatency(_ ms: Double?, stillRunning: Bool = false) {
        let reading: InternetReading
        if let ms {
            let threshold = internetBlock()?.arrowMs ?? 2
            reading = InternetReading(ms: ms, trend: Trend.from(previous: latencyPrevious, current: ms, thresholdMs: threshold),
                                      failed: false)
        } else {
            reading = InternetReading(ms: nil, trend: .none, failed: true)
        }
        latencyPrevious = ms
        if internetReading == nil || internetReading?.failed != reading.failed {
            let host = latencyProbe?.host ?? "?"
            print(reading.failed
                  ? "Internet: no reply from \(host)\(stillRunning ? " (lookup or echo still running)" : "")"
                  : "Internet: \(host) answers in \(StripRenderer.latencyFigure(ms ?? 0)) ms")
        }
        let changed = internetReading?.shown != reading.shown
        internetReading = reading
        if changed { redrawLive(.internet) }
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
        case .internet:
            let r = internetReading
            return StripRenderer.internet(ms: r?.ms, trend: r?.trend ?? .none, failed: r?.failed ?? false)
        case .picture, .empty:
            return nil
        }
    }

    /// Redraws only the slots showing `type`, on every deck that shows it.
    private func redrawLive(_ type: StripBlockType) {
        guard !livePaused, let jpeg = liveImage(type) else { return }   // never over the lock photo
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
        switch input {
        case .keyDown, .stripTap, .swipe: lockMonitor.recheck()     // don't trust a stale "unlocked"
        default: break
        }
        guard let resolved = ActionResolver.resolve(input, deck: kind, config: config) else {
            switch input {
            case .keyUp, .knobUp: break
            default: print("Input \(kind.rawValue) \(input) → nothing")
            }
            return
        }
        let step = resolved.step.map { " step \($0)" } ?? ""
        guard LockPolicy.allows(input, action: resolved.action, locked: lockMonitor.locked) else {
            print("Input \(kind.rawValue) \(input) → \(resolved.action)\(step): ignored while locked")
            return
        }
        print("Input \(kind.rawValue) \(input) → \(resolved.action)\(step)")
        dispatcher.execute(resolved)
    }
}
