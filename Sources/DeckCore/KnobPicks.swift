import Foundation

/// Where each list knob is in its list (docs/design/knob_lists.md): per deck, preset and knob, starting at the first
/// item. Kept in memory only: a swipe away and back finds it where it was, a restart starts every list at its first
/// item, and nothing is written to the file (saving on every click would churn it and widen KI-013's race). Keyed by
/// the preset's name, so a renamed preset starts again at the first item. Main thread only.
struct KnobPicks: Equatable {
    private struct Key: Hashable {
        let deck: DeckKind
        let preset: String
        let knob: String
    }

    private var index: [Key: Int] = [:]

    /// The strip block above a knob shows its list: `"1"` ↔ `knob_1` … `"4"` ↔ `knob_4`, left to right.
    static func knob(under block: String) -> String { "knob_" + block }

    /// The pick in a list of `count` items: where the knob was left, or the first item when the list has shrunk
    /// below that (an edit). Nil for an empty list.
    func pick(_ deck: DeckKind, preset: String, knob: String, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let at = index[Key(deck: deck, preset: preset, knob: knob)] ?? 0
        return at < count ? at : 0
    }

    /// Moves the pick by `sign` items, wrapping from the last to the first and back. Nil for an empty list.
    @discardableResult
    mutating func turn(_ deck: DeckKind, preset: String, knob: String, by sign: Int, count: Int) -> Int? {
        guard let from = pick(deck, preset: preset, knob: knob, count: count) else { return nil }
        let to = ((from + sign) % count + count) % count
        index[Key(deck: deck, preset: preset, knob: knob)] = to
        return to
    }
}
