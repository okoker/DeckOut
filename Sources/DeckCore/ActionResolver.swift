// Which action an input runs, and whether it may run while the Mac is locked.

/// An action string from the config (`shell:…`, `key:…`, `system_volume`, …) and its signed step: a knob turn's
/// `step` times the turn's direction, or the `step` set on a key, knob press, strip block or swipe.
struct ResolvedAction: Equatable {
    let action: String
    let step: Int?
}

enum ActionResolver {

    /// The action `input` runs on `deck`, read from that deck's own config section.
    /// Nil for releases, `none`, and controls with nothing configured.
    static func resolve(_ input: DeckInput, deck: DeckKind, config: AppConfig) -> ResolvedAction? {
        let keys: [String: ButtonConfig]
        let knobs: [String: KnobConfig]
        switch deck {
        case .n3:
            keys = config.n3?.buttons ?? [:]
            knobs = config.n3?.knobs ?? [:]
        case .n4:
            keys = config.n4?.keys ?? [:]
            knobs = config.n4?.knobs ?? [:]
        }

        let resolved: ResolvedAction?
        switch input {
        case .keyDown(let key):
            resolved = keys[key].map { ResolvedAction(action: $0.action, step: $0.step) }
        case .knobTurn(let knob, let sign):
            resolved = knobs[knob].map { ResolvedAction(action: $0.rotate.action, step: ($0.rotate.step ?? 1) * sign) }
        case .knobDown(let knob):
            resolved = knobs[knob].map { ResolvedAction(action: $0.press.action, step: $0.press.step) }
        case .stripTap(let block):
            let tapped = deck == .n4 ? config.n4?.strip[block] : nil
            resolved = tapped?.action.map { ResolvedAction(action: $0, step: tapped?.step) }
        case .swipe:
            resolved = deck == .n4 ? config.n4?.swipe.map { ResolvedAction(action: $0.action, step: $0.step) } : nil
        case .keyUp, .knobUp:
            resolved = nil
        }

        guard let resolved, resolved.action != "none" else { return nil }
        return resolved
    }
}

enum LockPolicy {

    /// Actions that only adjust volume or brightness. The only ones that run while the Mac is locked,
    /// and only from a knob.
    static let builtIns: Set<String> = [
        "system_volume", "system_mute_toggle",
        "zr7_volume", "zr7_mute_toggle",
        "display_brightness", "display_brightness_cycle",
    ]

    /// While locked, keys, strip taps and swipes never run, and knobs run only built-in actions —
    /// so `shell:` and `key:` (which would type into the lock screen) never run from any control.
    static func allows(_ input: DeckInput, action: String, locked: Bool) -> Bool {
        guard locked else { return true }
        switch input {
        case .knobTurn, .knobDown, .knobUp:
            return builtIns.contains(action)
        case .keyDown, .keyUp, .stripTap, .swipe:
            return false
        }
    }
}
