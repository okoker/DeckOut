import Foundation

/// Drives every connected deck: start-up, layout, keepalive, and inputs → actions.
/// Lives for the whole process; everything runs on the main thread.
public final class Daemon {
    /// Posted (e.g. by `StreamDeckController --post-reload`, later by the config app) to re-read the config.
    public static let reloadNotification = "com.streamdeck.controller.reload"

    private var config: AppConfig
    private var dispatcher: ActionDispatcher
    private let decks = DeckManager()
    /// Key icons and picture blocks, rendered again only when a file's bytes change.
    private let slotImages = SlotImageCache()
    private var keepaliveTimer: Timer?
    private let lockMonitor = LockMonitor()

    /// A lock photo framing shown on the N4 while unlocked: the config app's photo mode, or `--show-lock-photo`.
    /// Keys and knobs work as usual; live readings pause.
    private var lockPhotoPreview: LockPhotoConfig?
    /// The preview's photo, decoded once while the preview is up (a drag sends a framing per move).
    private let previewPhotos = LockPhoto.PreviewCache()

    /// Live readings pause while the lock photo or the locked layout is up.
    private var livePaused: Bool { lockMonitor.locked || lockPhotoPreview != nil }

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

    /// Monitor brightness (DDC via `m1ddc`). One control lives across reloads: building it runs `m1ddc` to list the
    /// monitors, which can stall, so it is built off the main thread, and again only when `displays` changes.
    private var brightness: BrightnessControl?
    private var brightnessBuilding = false
    private(set) var brightnessGeneration = 0      // a build that finishes after a newer one started is dropped

    /// The user's shell environment, shared with every dispatcher; `refresh` is the owner's business.
    private let environment: ShellEnvironment

    public init(config: AppConfig, environment: ShellEnvironment) {
        self.config = config
        self.environment = environment
        self.dispatcher = ActionDispatcher(config: config, brightness: nil, environment: environment)
    }

    /// True when the monitors to control differ (order included: it decides the cycle order). Nil and empty
    /// both mean "no monitors".
    static func displaysChanged(_ old: [DisplayConfig]?, _ new: [DisplayConfig]?) -> Bool {
        (old ?? []) != (new ?? [])
    }

    /// Called after a deck connects or is removed.
    var onDecksChanged: (() -> Void)?
    /// Called once per redraw with the images it made for live strip blocks, one per block type, whether they were
    /// sent or already showing (the config app shows them in its drawing).
    var onLiveImages: (([StripBlockType: Data]) -> Void)?

    /// The decks plugged in now.
    var connectedKinds: [DeckKind] { decks.connections.map { $0.model.kind } }

    public func start() {
        rebuildBrightness(for: config.displays)
        decks.onConnect = { [weak self] connection in
            self?.connected(connection)
            self?.onDecksChanged?()
        }
        decks.onRemove = { [weak self] _ in
            self?.updateLiveSources()
            self?.onDecksChanged?()
        }
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

    /// Switch to a new, already validated config and redraw every connected deck in place, sending only the slots
    /// whose image changed. The monitor control is rebuilt when `displays` changed, or when `rebuildMonitors` asks
    /// (a reload from outside: it finds monitors plugged in, or `m1ddc` installed, since start, as every reload did
    /// in v1.0.0).
    public func reload(_ newConfig: AppConfig, rebuildMonitors: Bool = false) {
        let started = Date()
        let displaysChanged = Self.displaysChanged(config.displays, newConfig.displays)
        config = newConfig
        dispatcher = makeDispatcher()
        if displaysChanged || rebuildMonitors { rebuildBrightness(for: newConfig.displays) }
        for connection in decks.connections {
            connection.setBrightness(brightness(for: connection.model.kind))
            showCurrent(connection)
        }
        updateLiveSources()
        print("Reloaded in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
    }

    private func makeDispatcher() -> ActionDispatcher {
        let dispatcher = ActionDispatcher(config: config, brightness: brightness, environment: environment)
        dispatcher.brightnessBuilding = brightnessBuilding
        return dispatcher
    }

    /// Shuts the old monitor control down and builds one for `displays` off the main thread. Until it is
    /// ready, brightness actions log "monitors not ready yet".
    private func rebuildBrightness(for displays: [DisplayConfig]?) {
        // Off main: shutdown waits on the control's queue, which a hung m1ddc call could hold.
        if let old = brightness { DispatchQueue.global(qos: .utility).async { old.shutdown() } }
        brightness = nil
        brightnessGeneration += 1
        let generation = brightnessGeneration
        guard let displays, !displays.isEmpty else {
            brightnessBuilding = false
            dispatcher.brightnessControl = nil
            dispatcher.brightnessBuilding = false
            return
        }
        brightnessBuilding = true
        dispatcher.brightnessControl = nil
        dispatcher.brightnessBuilding = true
        DispatchQueue.global(qos: .userInitiated).async {
            let started = Date()
            let control = BrightnessControl(displays: displays)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.brightnessGeneration == generation else {
                    control?.shutdown()          // displays changed again meanwhile
                    return
                }
                print("Monitors ready in \(ms) ms")
                self.brightness = control
                self.brightnessBuilding = false
                self.dispatcher.brightnessControl = control
                self.dispatcher.brightnessBuilding = false
            }
        }
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

    /// The layout, or — while the Mac is locked — the N4's lock photo if one is set. Only the slots whose image
    /// changed are sent; with `everySlot`, every slot (unlock: a deck may have reset itself meanwhile).
    private func showCurrent(_ connection: DeckConnection, everySlot: Bool = false) {
        if livePaused, drawLockPhoto(connection, everySlot: everySlot) { return }
        drawAll(connection, everySlot: everySlot)
    }

    private func brightness(for kind: DeckKind) -> Int {
        switch kind {
        case .n3: return config.n3?.brightness ?? 50
        case .n4: return config.n4?.brightness ?? 50
        }
    }

    /// Makes the image of every slot of the deck's layout plan (a black image where nothing is set; icons from the
    /// cache, live blocks from their latest reading) and sends, in place, those that differ from what the deck
    /// shows — every slot with `everySlot` — then one commit if any was sent. No clear, unless the model needs one.
    func drawAll(_ connection: DeckConnection, everySlot: Bool = false) {
        let started = Date()
        let model = connection.model
        let plan = LayoutPlan.slots(model: model, config: config)
        if model.clearsBeforeRedraw { connection.clearAll() }
        var images = slotImages.images(plan: plan, model: model)
        var live: [StripBlockType: Data] = [:]
        for (slot, content) in plan.sorted(by: { $0.key < $1.key }) {
            guard case .strip(let type) = content else { continue }
            let jpeg = liveImage(type)
            if let jpeg { live[type] = jpeg }
            images[slot] = jpeg ?? LayoutPlan.blank(slot: slot, model: model)
        }
        let sent = connection.drawChanged(images, everySlot: everySlot)
        if !live.isEmpty { onLiveImages?(live) }
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        print("Drew \(sent) of \(plan.count) slots on \(model.kind.rawValue) in \(ms) ms")
    }

    // MARK: - Lock

    /// Locked: live readings pause and the N4 shows its lock photo (without one, every deck keeps its
    /// layout, inert). Unlocked: every deck redraws every slot (a deck that reset itself while locked, e.g.
    /// through sleep, is put right) and live readings resume.
    private func lockChanged(_ locked: Bool) {
        print(locked ? "Screen locked" : "Screen unlocked")
        updateLiveSources()
        for connection in decks.connections {
            if locked {
                _ = drawLockPhoto(connection)
            } else {
                showCurrent(connection, everySlot: true)
            }
        }
    }

    /// Shows `framing` on the N4 until called with nil, which goes back to the layout (or, while locked, to the
    /// configured lock photo). Live readings pause meanwhile.
    public func showLockPhoto(_ framing: LockPhotoConfig?) {
        lockPhotoPreview = framing
        if framing == nil { previewPhotos.clear() }
        updateLiveSources()
        for connection in decks.connections where connection.model.kind == .n4 {
            showCurrent(connection)
        }
    }

    /// Draws the lock photo across an N4's keys and strip: the preview framing if one is up, else the config's.
    /// Sends only the pieces that differ from what the deck shows (every piece with `everySlot`).
    /// False (nothing drawn) for another deck, with no photo set, or when the photo can't be read.
    @discardableResult
    private func drawLockPhoto(_ connection: DeckConnection, everySlot: Bool = false) -> Bool {
        guard connection.model.kind == .n4, let framing = lockPhotoPreview ?? config.n4?.lockPhoto else { return false }
        let started = Date()
        let slices = LockPhoto.slicesToDraw(framing, previewing: lockPhotoPreview != nil, cache: previewPhotos)
        guard !slices.isEmpty else { return false }
        let sent = connection.drawChanged(slices, everySlot: everySlot)
        print("Drew lock photo on n4 (\(sent) of \(slices.count) slots) in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
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

    /// Redraws only the slots showing `type`, on every deck that shows it, and only where the image differs.
    private func redrawLive(_ type: StripBlockType) {
        guard !livePaused, let jpeg = liveImage(type) else { return }   // never over the lock photo
        onLiveImages?([type: jpeg])
        for connection in decks.connections {
            let slots = LayoutPlan.slots(model: connection.model, config: config).filter { $0.value == .strip(type) }
            connection.drawChanged(slots.mapValues { _ in jpeg }, everySlot: false)
        }
    }

    // MARK: - Input

    /// Runs one action exactly as a press would, minus the lock check (the config app's Test button).
    func run(action: String, step: Int?, completion: @escaping (ActionResult) -> Void) {
        print("Test → \(action)\(step.map { " step \($0)" } ?? "")")
        dispatcher.execute(ResolvedAction(action: action, step: step), completion: completion)
    }

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
