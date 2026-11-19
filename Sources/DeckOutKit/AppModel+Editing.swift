import AppKit
import DeckCore
import Foundation

/// What the editors change. Every change goes through the store: saved, reloaded, undoable.
extension AppModel {

    // MARK: - Keys, buttons, strip taps

    public func choice(button id: String, on deck: DeckKind) -> ActionChoice {
        let button = config?.button(deck, id)
        return ActionChoice(action: button?.action ?? "none", step: button?.step)
    }

    /// Sets a key's (or button's) action, keeping its icon, except that an app's own icon follows the app: choosing
    /// Open App puts that app's icon on the key unless the person chose an image of their own.
    public func setAction(_ choice: ActionChoice, button id: String, on deck: DeckKind) {
        guard let store else { return }
        var icon = config?.button(deck, id)?.icon
        if case .openApp(let path) = choice, !path.isEmpty, deck == .n4 || id.hasPrefix("lcd_"), Self.followsApp(icon) {
            icon = IconFiles.appIcon(appPath: path, folder: IconFiles.folder(forConfig: store.path)) ?? icon
        }
        store.change("Change Action") { config in
            config.setButton(deck, id, choice == .nothing && icon == nil
                             ? nil : ButtonConfig(action: choice.action, icon: icon, step: choice.step))
        }
    }

    public func setIcon(_ path: String?, button id: String, on deck: DeckKind) {
        store?.change("Change Icon") { config in
            let current = config.button(deck, id) ?? ButtonConfig(action: "none")
            config.setButton(deck, id, path == nil && current.action == "none"
                             ? nil : ButtonConfig(action: current.action, icon: path, step: current.step))
        }
    }

    public func clearButton(_ id: String, on deck: DeckKind) {
        store?.change("Clear Key") { $0.setButton(deck, id, nil) }
    }

    /// The icon the app made from an app (or a hand-set icon inside an app bundle) follows the app; an image the
    /// person chose stays.
    static func followsApp(_ icon: String?) -> Bool {
        guard let icon else { return true }
        return icon.contains("/icons/app-") || icon.contains(".app/Contents/")
    }

    /// Copies a chosen image into the icons folder; nil if it can't be read.
    public func importImage(_ source: String) -> String? {
        guard let store else { return nil }
        return IconFiles.copyImage(from: source, folder: IconFiles.folder(forConfig: store.path))
    }

    public func appIcon(for appPath: String) -> String? {
        guard let store else { return nil }
        return IconFiles.appIcon(appPath: appPath, folder: IconFiles.folder(forConfig: store.path))
    }

    // MARK: - Test

    /// Runs the action in the agent exactly as a press would; nil if the agent didn't answer.
    public func test(_ choice: ActionChoice) async -> ActionResult? {
        guard let link, let request = try? JSONEncoder().encode(TestRequest(action: choice.action, step: choice.step))
        else { return nil }
        return await withCheckedContinuation { (done: CheckedContinuation<ActionResult?, Never>) in
            let once = OnceBox(done)
            link.call({ proxy in
                proxy.test(request) { data in once.resume(try? JSONDecoder().decode(ActionResult.self, from: data)) }
            }, failure: { _ in once.resume(nil) })
            DispatchQueue.main.asyncAfter(deadline: .now() + 35) { once.resume(nil) }   // commands stop at 30 s
        }
    }

    // MARK: - Apple Shortcuts

    /// Reads the person's Shortcuts once (`/usr/bin/shortcuts list`, as an argument array).
    public func loadShortcutNames() {
        guard shortcutNames == nil else { return }
        shortcutNames = []
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["list"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            var names: [String] = []
            if (try? process.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                names = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
                    .filter { !$0.isEmpty }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            }
            DispatchQueue.main.async { self?.shortcutNames = names }
        }
    }
}

/// Resumes a continuation once, whichever comes first: the reply, the error or the timeout.
final class OnceBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?
    init(_ continuation: CheckedContinuation<T, Never>) { self.continuation = continuation }
    func resume(_ value: T) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

// MARK: - Knobs and strip blocks

extension AppModel {

    public func knobChoices(_ id: String, on deck: DeckKind) -> (turn: ActionChoice, press: ActionChoice) {
        let knob = config?.knob(deck, id)
        return (ActionChoice(action: knob?.rotate.action ?? "none", step: knob?.rotate.step),
                ActionChoice(action: knob?.press.action ?? "none", step: knob?.press.step))
    }

    public func setKnob(_ id: String, on deck: DeckKind, turn: ActionChoice? = nil, press: ActionChoice? = nil) {
        store?.change("Change Knob") { config in
            let current = config.knob(deck, id)
            let rotate = turn.map { KnobAction(action: $0.action, step: $0.step) } ?? current?.rotate ?? KnobAction(action: "none")
            let pressed = press.map { KnobAction(action: $0.action, step: $0.step) } ?? current?.press ?? KnobAction(action: "none")
            config.setKnob(deck, id, rotate.action == "none" && pressed.action == "none"
                           ? nil : KnobConfig(rotate: rotate, press: pressed))
        }
    }

    public func clearKnob(_ id: String, on deck: DeckKind) {
        store?.change("Clear Knob") { $0.setKnob(deck, id, nil) }
    }

    public func stripBlock(_ id: String) -> StripBlockConfig? { config?.stripBlock(id) }

    /// What the block shows. Switching type keeps the tap; a picture keeps its image; the internet settings start
    /// fresh unless it already was an internet block.
    public func setStripType(_ type: StripBlockType, block id: String) {
        store?.change("Change Strip Block") { config in
            let old = config.stripBlock(id)
            guard old?.type != type else { return }
            if type == .empty, old?.action == nil {
                config.setStripBlock(id, nil)
                return
            }
            config.setStripBlock(id, StripBlockConfig(type: type, action: old?.action, step: old?.step,
                                                      icon: type == .picture ? old?.icon : nil))
        }
    }

    public func editStripBlock(_ id: String, _ name: String = "Change Strip Block", _ edit: @escaping (inout StripBlockConfig) -> Void) {
        store?.change(name) { config in
            var block = config.stripBlock(id) ?? StripBlockConfig(type: .empty)
            edit(&block)
            config.setStripBlock(id, block.type == .empty && block.action == nil ? nil : block)
        }
    }

    public func setStripTap(_ choice: ActionChoice, block id: String) {
        editStripBlock(id, "Change Tap") { block in
            block.action = choice == .nothing ? nil : choice.action
            block.step = choice.step
        }
    }

    public func clearStripBlock(_ id: String) {
        store?.change("Clear Strip Block") { $0.setStripBlock(id, nil) }
    }

    /// Controls on the deck on screen whose files are gone (or whose script can't run).
    public var problems: [String: String] {
        guard let shown, let config else { return [:] }
        return MissingFiles.check(config, deck: shown)
    }

    public func makeExecutable(_ path: String) {
        _ = MissingFiles.makeExecutable(path)
        objectWillChange.send()
    }
}

// MARK: - Presets, brightness

extension AppModel {

    public var presetNames: [String] {
        guard let shown else { return [] }
        let names = config?.presetNames(shown) ?? []
        return names.isEmpty ? ["Default"] : names
    }

    public var livePreset: String {
        shown.flatMap { config?.livePreset($0) } ?? "Default"
    }

    public func makeLive(_ name: String) {
        guard let shown else { return }
        store?.change("Switch Preset") { $0.makeLive(name, deck: shown) }
    }

    /// Returns the new preset's name (it is live).
    public func newPreset() -> String? {
        guard let shown else { return nil }
        var made: String?
        store?.change("New Preset") { made = $0.newPreset(deck: shown) }
        return made
    }

    public func duplicateLivePreset() {
        guard let shown else { return }
        let live = livePreset
        store?.change("Duplicate Preset") { config in
            config.ensureDeck(shown)
            config.duplicatePreset(live, deck: shown)
        }
    }

    /// False when the name is empty or taken (nothing changes).
    public func renameLivePreset(to name: String) -> Bool {
        guard let shown else { return false }
        let live = livePreset
        var renamed = false
        store?.change("Rename Preset") { config in
            config.ensureDeck(shown)
            renamed = config.renamePreset(live, to: name, deck: shown)
        }
        return renamed || name.trimmingCharacters(in: .whitespaces) == live
    }

    public func deleteLivePreset() {
        guard let shown else { return }
        let live = livePreset
        store?.change("Delete Preset") { _ = $0.deletePreset(live, deck: shown) }
    }

    public var brightness: Int {
        shown.map { config?.brightness($0) ?? 75 } ?? 75
    }

    public func setBrightness(_ value: Int) {
        guard let shown else { return }
        store?.change("Change Brightness", coalescing: true) { $0.setBrightness(shown, value) }
    }
}

// MARK: - Accessibility

extension AppModel {

    /// The agent asks macOS to list it under Accessibility; the pane opens; the status is read again every 2 s for a
    /// minute, so the banner goes as soon as it's allowed.
    public func requestAccessibility() {
        link?.call({ proxy in proxy.requestAccessibility { _ in } })
        if let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(pane)
        }
        for second in stride(from: 2, through: 60, by: 2) {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(second)) { [weak self] in
                guard let self, self.link?.status?.accessibility == false else { return }
                self.link?.refreshStatus()
            }
        }
    }
}
