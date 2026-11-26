import Foundation

public final class BrightnessControl {

    // MARK: - Types

    struct ConnectedDisplay {
        let name: String
        let serial: String
        let m1ddcIndex: Int
        let cgDisplayID: UInt32
        var brightness: Int?      // 0–100 as last read or set; nil = not known, so read before moving
    }

    enum TargetMode: Equatable {
        case all
        case single(Int)          // index into connectedDisplays
    }

    // MARK: - Properties

    private let m1ddcPath: String
    private let configuredDisplays: [DisplayConfig]
    private(set) var connectedDisplays: [ConnectedDisplay] = []
    private var targetMode: TargetMode = .all

    private let queue = DispatchQueue(label: "deckout.brightness")
    let writeQueue = DispatchQueue(label: "deckout.m1ddc.write", qos: .userInteractive)   // internal: tests wait on it
    private let idleTimeout: TimeInterval
    private let hud: (String) -> Void
    private var inactivityTimer: DispatchSourceTimer?
    private var debounceTimer: DispatchSourceTimer?
    private var pendingDelta: Int = 0

    private static let debounceInterval: TimeInterval = 0.08

    // MARK: - Init

    /// `m1ddcPath`, `idleTimeout` and `hud` are for tests: a stand-in m1ddc, a short idle time, the messages shown.
    init?(displays: [DisplayConfig], m1ddcPath: String? = nil, idleTimeout: TimeInterval = 30,
          hud: @escaping (String) -> Void = { text in DispatchQueue.main.async { BrightnessHUD.show(text: text) } }) {
        guard !displays.isEmpty else {
            print("BrightnessControl: no displays configured")
            return nil
        }
        guard let path = m1ddcPath ?? Self.findM1DDC() else {
            print("BrightnessControl: m1ddc not found (not in the app, nor Homebrew's)")
            return nil
        }
        self.m1ddcPath = path
        self.idleTimeout = idleTimeout
        self.hud = hud
        print("BrightnessControl: using m1ddc at \(path)")
        self.configuredDisplays = displays
        refreshDisplays()
        if connectedDisplays.isEmpty {
            print("BrightnessControl: no configured displays are currently connected")
        }
    }

    deinit {
        inactivityTimer?.cancel()
        debounceTimer?.cancel()
    }

    /// Graceful teardown — cancel timers on their own queue (thread-safe).
    /// Called before replacing the dispatcher on SIGHUP reload.
    func shutdown() {
        queue.sync {
            inactivityTimer?.cancel()
            inactivityTimer = nil
            debounceTimer?.cancel()
            debounceTimer = nil
        }
    }

    // MARK: - Public API

    func adjust(step: Int) {
        queue.async { [self] in
            pendingDelta += step
            resetInactivityTimer()
            scheduleDebounce()
        }
    }

    func cycleMode() {
        queue.async { [self] in
            // Refresh display mapping on each cycle — handles hot-plug/renumber
            refreshDisplays()
            guard !connectedDisplays.isEmpty else { return }

            switch targetMode {
            case .all:
                targetMode = .single(0)
            case .single(let idx):
                let next = idx + 1
                targetMode = next < connectedDisplays.count ? .single(next) : .all
            }

            // Show mode label IMMEDIATELY — don't block on hardware reads
            let label = currentModeLabel()
            hud("◉ \(label)")

            let targets = currentTargetIndices()
            readUnknown(targets)
            if let error = monitorError(targets) {
                hud(error)
            } else if let first = targets.first, let brightness = connectedDisplays[first].brightness {
                hud("◉ \(label)  \(brightness)%")
            }

            resetInactivityTimer()
        }
    }

    // MARK: - Display discovery

    /// Finds which m1ddc display each configured monitor is now. Brightness isn't read here: a reading taken before
    /// the first turn could be stale, or a bad reply (BL-003), so every monitor starts unknown and a turn reads it.
    func refreshDisplays() {
        guard let output = runProcess(m1ddcPath, args: ["display", "list", "detailed"])?.output else {
            print("BrightnessControl: failed to list displays")
            return
        }

        let blocks = parseDisplayBlocks(output)

        var connected: [ConnectedDisplay] = []
        for cfg in configuredDisplays {
            if let block = blocks.first(where: { $0.anSerial == cfg.serial }) {
                connected.append(ConnectedDisplay(
                    name: cfg.name, serial: cfg.serial,
                    m1ddcIndex: block.number,
                    cgDisplayID: block.displayID,
                    brightness: nil))
                print("BrightnessControl: \(cfg.name) (\(cfg.serial)) → display \(block.number)")
            } else {
                print("BrightnessControl: \(cfg.name) (\(cfg.serial)) not connected")
            }
        }
        connectedDisplays = connected
    }

    // MARK: - m1ddc parsing

    private struct DisplayBlock {
        let number: Int
        let anSerial: String
        let displayID: UInt32
    }

    private func parseDisplayBlocks(_ output: String) -> [DisplayBlock] {
        var blocks: [DisplayBlock] = []
        var curNum: Int?
        var curSerial: String?
        var curDisplayID: UInt32?

        for line in output.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)

            if let r = t.range(of: #"^\[(\d+)\]"#, options: .regularExpression) {
                if let n = curNum, let s = curSerial, let d = curDisplayID {
                    blocks.append(DisplayBlock(number: n, anSerial: s, displayID: d))
                }
                curNum = Int(t[r].dropFirst().dropLast())
                curSerial = nil
                curDisplayID = nil
            }
            if t.hasPrefix("- AN Serial:") {
                curSerial = t.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces)
            }
            if t.hasPrefix("- Display ID:") {
                if let s = t.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) {
                    curDisplayID = UInt32(s)
                }
            }
        }
        if let n = curNum, let s = curSerial, let d = curDisplayID {
            blocks.append(DisplayBlock(number: n, anSerial: s, displayID: d))
        }
        return blocks
    }

    // MARK: - Brightness operations

    /// The monitor's brightness, or nil when there's no valid reading: m1ddc couldn't start or failed (it says
    /// "DDC communication failure" when the monitor gave no valid reply), or printed something that isn't 0–100.
    /// Never a guess: a guess moves a monitor from the wrong place (BL-003: 100 % read as 0 went to 5 %).
    private func readBrightness(displayNumber: Int) -> Int? {
        let t0 = CFAbsoluteTimeGetCurrent()
        let result = runProcess(m1ddcPath, args: ["display", "\(displayNumber)", "get", "luminance"])
        let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        let text = result?.output.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let result, result.status == 0, let value = Int(text), (0...100).contains(value) else {
            let why = result.map { "exit \($0.status): \(text)" } ?? "m1ddc didn't start"
            print("BrightnessControl: read display \(displayNumber) → no reading (\(why)) (\(ms)ms)")
            return nil
        }
        print("BrightnessControl: read display \(displayNumber) → \(value) (\(ms)ms)")
        return value
    }

    /// Reads each target whose brightness isn't known; one that gives no reading stays unknown, and is left alone.
    private func readUnknown(_ targets: [Int]) {
        for idx in targets where connectedDisplays[idx].brightness == nil {
            connectedDisplays[idx].brightness = readBrightness(displayNumber: connectedDisplays[idx].m1ddcIndex)
        }
    }

    /// "Left: Monitor Error" (every target with no reading, by name), or nil when all have one.
    private func monitorError(_ targets: [Int]) -> String? {
        let failed = targets.filter { connectedDisplays[$0].brightness == nil }.map { connectedDisplays[$0].name }
        return failed.isEmpty ? nil : "\(failed.joined(separator: ", ")): Monitor Error"
    }

    /// After a failed write the monitor's brightness isn't known: the next turn reads it.
    private func forgetBrightness(displayNumber: Int) {
        for idx in connectedDisplays.indices where connectedDisplays[idx].m1ddcIndex == displayNumber {
            connectedDisplays[idx].brightness = nil
        }
    }

    /// Async write — doesn't block caller. On failure the monitor's brightness is forgotten.
    private func writeBrightnessAsync(displayNumber: Int, value: Int) {
        let path = m1ddcPath
        writeQueue.async { [weak self] in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.arguments = ["display", "\(displayNumber)", "set", "luminance", "\(value)"]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus != 0 {
                    print("BrightnessControl: m1ddc set failed (exit \(proc.terminationStatus)) for display \(displayNumber)")
                    self?.queue.async { self?.forgetBrightness(displayNumber: displayNumber) }
                }
            } catch {
                print("BrightnessControl: m1ddc launch failed: \(error)")
                self?.queue.async { self?.forgetBrightness(displayNumber: displayNumber) }
            }
        }
    }

    private func applyPendingDelta() {
        let delta = pendingDelta
        pendingDelta = 0
        guard delta != 0 else { return }

        let targets = currentTargetIndices()
        guard !targets.isEmpty else { return }

        // First turn after start-up or idle, or after a failed write: read the monitors first
        readUnknown(targets)

        for idx in targets {
            guard let current = connectedDisplays[idx].brightness else { continue }   // no reading: left alone
            let newVal = max(0, min(100, current + delta))
            if newVal != current {
                writeBrightnessAsync(displayNumber: connectedDisplays[idx].m1ddcIndex, value: newVal)
                connectedDisplays[idx].brightness = newVal
            }
        }

        if let error = monitorError(targets) {
            hud(error)
        } else if let brightness = connectedDisplays[targets[0]].brightness {
            hud("☀ \(brightness)%  \(currentModeLabel())")
        }
    }

    // MARK: - Target helpers

    private func currentTargetIndices() -> [Int] {
        switch targetMode {
        case .all:
            return Array(connectedDisplays.indices)
        case .single(let idx):
            return idx < connectedDisplays.count ? [idx] : []
        }
    }

    private func currentModeLabel() -> String {
        switch targetMode {
        case .all:
            return "All"
        case .single(let idx):
            return idx < connectedDisplays.count ? connectedDisplays[idx].name : "?"
        }
    }

    // MARK: - Timers

    private func resetInactivityTimer() {
        inactivityTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + idleTimeout)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            // Idle: the monitors may have been changed with their own buttons, so the next turn reads them
            for idx in self.connectedDisplays.indices { self.connectedDisplays[idx].brightness = nil }
            if self.targetMode != .all {
                self.targetMode = .all
                self.hud("◉ All")
                print("BrightnessControl: inactivity → reverted to all displays")
            }
        }
        timer.resume()
        inactivityTimer = timer
    }

    private func scheduleDebounce() {
        guard debounceTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.debounceInterval)
        timer.setEventHandler { [weak self] in
            self?.applyPendingDelta()
            self?.debounceTimer = nil
        }
        timer.resume()
        debounceTimer = timer
    }

    // MARK: - Process helpers

    /// What the program printed and its exit status; nil if it couldn't start.
    private func runProcess(_ path: String, args: [String]) -> (output: String, status: Int32)? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            // Read stdout BEFORE waitUntilExit to avoid pipe buffer deadlock
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return (String(decoding: data, as: UTF8.self), proc.terminationStatus)
        } catch {
            return nil
        }
    }

    /// The app's own copy (`DeckOut.app/Contents/Helpers/m1ddc`), else Homebrew's. The app's Settings use it too, so
    /// monitors are listed with the m1ddc the agent drives them with.
    public static func findM1DDC(bundleURL: URL = Bundle.main.bundleURL,
                          executable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        [bundleURL.appendingPathComponent("Contents/Helpers/m1ddc").path, "/opt/homebrew/bin/m1ddc", "/usr/local/bin/m1ddc"]
            .first(where: executable)
    }
}
