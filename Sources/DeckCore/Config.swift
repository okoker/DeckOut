import Foundation

// The config file: shared settings at the top, one section per deck under `decks`.
//
//   { "displays": [...], "decks": { "n3": { ... }, "n4": { ... } } }
//
// Each deck section holds its presets (the keys, the knobs, and on the N4 the strip) and names the live one in
// `active_preset`; brightness, the swipe and the lock photo belong to the deck. A section without `presets` (files
// from before presets) reads as one preset named "Default" made from its `keys` + `strip` (N4) or `buttons` (N3),
// and its `knobs`.
//
// Knobs moved from the deck into each preset in 2.2 (docs/design/knob_lists.md). A file from before keeps them on
// the deck: every preset without a `knobs` key of its own gets a copy. They are written in every preset, never on
// the deck.
//
// Old (v1.0.0) format: a file with no `decks` key is the N3 section itself
// (top-level `brightness`, `buttons`, `knobs`). When `decks` is present, those
// top-level keys are ignored.
//
// Encoding always writes the `decks` form with `presets` + `active_preset`, so a file read in an old form is
// written back in the current one. Only known keys are written.

public struct AppConfig: Equatable {
    public var displays: [DisplayConfig]?
    public var n3: N3Section?
    public var n4: N4Section?

    public init(displays: [DisplayConfig]? = nil, n3: N3Section? = nil, n4: N4Section? = nil) {
        self.displays = displays
        self.n3 = n3
        self.n4 = n4
    }

    /// No decks set up: every connected deck stays blank.
    public static let empty = AppConfig()

    public static func parse(_ data: Data) throws -> AppConfig {
        try JSONDecoder().decode(AppConfig.self, from: data)
    }

    /// The file's contents: pretty-printed with sorted keys (so saves diff cleanly), always the `decks` form.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

extension AppConfig: Codable {
    private enum CodingKeys: String, CodingKey { case displays, decks }

    private struct Decks: Codable {
        var n3: N3Section?
        var n4: N4Section?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displays = try c.decodeIfPresent([DisplayConfig].self, forKey: .displays)
        if let decks = try c.decodeIfPresent(Decks.self, forKey: .decks) {
            n3 = decks.n3
            n4 = decks.n4
        } else {
            n3 = try N3Section(from: decoder)   // v1.0.0: the whole file is the N3 section
            n4 = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(displays, forKey: .displays)
        try c.encode(Decks(n3: n3, n4: n4), forKey: .decks)
    }
}

public struct DisplayConfig: Codable, Equatable {
    public let name: String
    public let serial: String          // AN Serial from `m1ddc display list detailed`

    public init(name: String, serial: String) {
        self.name = name
        self.serial = serial
    }
}

// MARK: - Presets

/// Refuses an empty preset list, a preset without a name, and two presets with the same name: the app picks the
/// live preset by name, so each must be unique and visible.
private func checkPresetNames<K: CodingKey>(_ names: [String], in c: KeyedDecodingContainer<K>, key: K) throws {
    guard !names.isEmpty else {
        throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "presets must list at least one preset")
    }
    if names.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
        throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "every preset needs a name")
    }
    var seen = Set<String>()
    for name in names where !seen.insert(name).inserted {
        throw DecodingError.dataCorruptedError(forKey: key, in: c,
                                               debugDescription: "two presets are both called \"\(name)\"")
    }
}

/// One N3 layout: the six LCD keys, three buttons and three knobs.
public struct N3Preset: Codable, Equatable {
    public var name: String
    public var buttons: [String: ButtonConfig]
    public var knobs: [String: KnobConfig]

    public init(name: String, buttons: [String: ButtonConfig], knobs: [String: KnobConfig] = [:]) {
        self.name = name
        self.buttons = buttons
        self.knobs = knobs
    }

    private enum CodingKeys: String, CodingKey { case name, buttons, knobs }

    /// A preset without `knobs` reads as none here; the section fills it from the deck's (`KnobsKey`).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        buttons = try c.decodeIfPresent([String: ButtonConfig].self, forKey: .buttons) ?? [:]
        knobs = try c.decodeIfPresent([String: KnobConfig].self, forKey: .knobs) ?? [:]
    }
}

/// One N4 layout: the ten keys, the four strip blocks and the four knobs.
public struct N4Preset: Codable, Equatable {
    public var name: String
    public var keys: [String: ButtonConfig]
    public var strip: [String: StripBlockConfig]
    public var knobs: [String: KnobConfig]

    public init(name: String, keys: [String: ButtonConfig], strip: [String: StripBlockConfig],
                knobs: [String: KnobConfig] = [:]) {
        self.name = name
        self.keys = keys
        self.strip = strip
        self.knobs = knobs
    }

    private enum CodingKeys: String, CodingKey { case name, keys, strip, knobs }

    /// A preset without `knobs` reads as none here; the section fills it from the deck's (`KnobsKey`).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        keys = try c.decodeIfPresent([String: ButtonConfig].self, forKey: .keys) ?? [:]
        strip = try c.decodeIfPresent([String: StripBlockConfig].self, forKey: .strip) ?? [:]
        knobs = try c.decodeIfPresent([String: KnobConfig].self, forKey: .knobs) ?? [:]
    }
}

/// Whether a preset in the file has a `knobs` key of its own (even `{}`). Those without one get the deck's knobs:
/// a file from before knobs moved into presets.
private struct KnobsKey: Decodable {
    let present: Bool

    private enum CodingKeys: String, CodingKey { case knobs }

    init(from decoder: Decoder) throws {
        present = try decoder.container(keyedBy: CodingKeys.self).contains(.knobs)
    }
}

/// Gives every preset in `presets` without a `knobs` key of its own the deck's `knobs` (2.1.0 files).
private func fillKnobs<K: CodingKey, P>(_ presets: inout [P], _ knobs: WritableKeyPath<P, [String: KnobConfig]>,
                                        from deck: [String: KnobConfig]?, in c: KeyedDecodingContainer<K>,
                                        key: K) throws {
    guard let deck else { return }
    let present = try c.decode([KnobsKey].self, forKey: key)
    for index in presets.indices where !present[index].present {
        presets[index][keyPath: knobs] = deck
    }
}

// MARK: - Deck sections

/// TreasLin N3. Keys `lcd_1`–`lcd_6`, `btn_1`–`btn_3`; knobs `big`, `small_1`, `small_2` (per preset).
public struct N3Section: Codable, Equatable {
    public var brightness: Int
    public var presets: [N3Preset]
    /// The live preset's name. If no preset has it, the first preset is live.
    public var activePreset: String

    public init(brightness: Int, presets: [N3Preset], activePreset: String) {
        self.brightness = brightness
        self.presets = presets
        self.activePreset = activePreset
    }

    /// The live preset: the one named `activePreset`, else the first.
    public var active: N3Preset {
        presets.first { $0.name == activePreset } ?? presets.first ?? N3Preset(name: "Default", buttons: [:])
    }

    public var buttons: [String: ButtonConfig] { active.buttons }
    public var knobs: [String: KnobConfig] { active.knobs }

    private enum CodingKeys: String, CodingKey {
        case brightness, knobs, buttons, presets
        case activePreset = "active_preset"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        brightness = try c.decode(Int.self, forKey: .brightness)
        if var presets = try c.decodeIfPresent([N3Preset].self, forKey: .presets) {
            try checkPresetNames(presets.map(\.name), in: c, key: .presets)
            try fillKnobs(&presets, \.knobs, from: try c.decodeIfPresent([String: KnobConfig].self, forKey: .knobs),
                          in: c, key: .presets)
            self.presets = presets
            activePreset = try c.decodeIfPresent(String.self, forKey: .activePreset) ?? presets[0].name
        } else {
            // Before presets, `buttons` and `knobs` were required, as they still are in this form.
            presets = [N3Preset(name: "Default", buttons: try c.decode([String: ButtonConfig].self, forKey: .buttons),
                                knobs: try c.decode([String: KnobConfig].self, forKey: .knobs))]
            activePreset = "Default"
        }
        // The N3 has no screen above its knobs to show a list's pick.
        for preset in presets {
            if let knob = preset.knobs.first(where: { $0.value.list != nil })?.key {
                throw DecodingError.dataCorruptedError(forKey: .presets, in: c,
                                                       debugDescription: "knob \(knob) has a list: lists need the N4's strip")
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(brightness, forKey: .brightness)
        try c.encode(presets, forKey: .presets)
        try c.encode(activePreset, forKey: .activePreset)
    }
}

/// MiraBox N4. Keys `key_1`–`key_5` (top row), `key_6`–`key_10` (bottom row); knobs `knob_1`–`knob_4`
/// left → right; strip blocks `"1"`–`"4"` left → right. Keys, knobs and strip per preset.
public struct N4Section: Codable, Equatable {
    public var brightness: Int
    public var swipe: ActionConfig?
    public var lockPhoto: LockPhotoConfig?
    public var presets: [N4Preset]
    /// The live preset's name. If no preset has it, the first preset is live.
    public var activePreset: String

    public init(brightness: Int, swipe: ActionConfig?, lockPhoto: LockPhotoConfig?,
                presets: [N4Preset], activePreset: String) {
        self.brightness = brightness
        self.swipe = swipe
        self.lockPhoto = lockPhoto
        self.presets = presets
        self.activePreset = activePreset
    }

    /// The live preset: the one named `activePreset`, else the first.
    public var active: N4Preset {
        presets.first { $0.name == activePreset } ?? presets.first ?? N4Preset(name: "Default", keys: [:], strip: [:])
    }

    public var keys: [String: ButtonConfig] { active.keys }
    public var strip: [String: StripBlockConfig] { active.strip }
    public var knobs: [String: KnobConfig] { active.knobs }

    private enum CodingKeys: String, CodingKey {
        case brightness, keys, knobs, strip, swipe, presets
        case lockPhoto = "lock_photo"
        case activePreset = "active_preset"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        brightness = try c.decode(Int.self, forKey: .brightness)
        let deckKnobs = try c.decodeIfPresent([String: KnobConfig].self, forKey: .knobs)
        swipe = try c.decodeIfPresent(ActionConfig.self, forKey: .swipe)
        lockPhoto = try c.decodeIfPresent(LockPhotoConfig.self, forKey: .lockPhoto)
        if var presets = try c.decodeIfPresent([N4Preset].self, forKey: .presets) {
            try checkPresetNames(presets.map(\.name), in: c, key: .presets)
            try fillKnobs(&presets, \.knobs, from: deckKnobs, in: c, key: .presets)
            self.presets = presets
            activePreset = try c.decodeIfPresent(String.self, forKey: .activePreset) ?? presets[0].name
        } else {
            presets = [N4Preset(name: "Default",
                                keys: try c.decodeIfPresent([String: ButtonConfig].self, forKey: .keys) ?? [:],
                                strip: try c.decodeIfPresent([String: StripBlockConfig].self, forKey: .strip) ?? [:],
                                knobs: deckKnobs ?? [:])]
            activePreset = "Default"
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(brightness, forKey: .brightness)
        try c.encodeIfPresent(swipe, forKey: .swipe)
        try c.encodeIfPresent(lockPhoto, forKey: .lockPhoto)
        try c.encode(presets, forKey: .presets)
        try c.encode(activePreset, forKey: .activePreset)
    }
}

// MARK: - Lock photo

/// The N4's lock photo and how it sits on the deck's face (800×464 key-image pixels). The photo first fills the
/// face (aspect-fill, centred), then is scaled by `zoom` about the centre and moved by the offsets, fractions of the
/// face (`offset_y` 0.5 moves it down by half the face's height, as the user sees it). Placement then clamps it so
/// it always covers the face: no black edges.
///
/// JSON: a path string (zoom 1, centred), or `{ "path", "zoom", "offset_x", "offset_y" }`; always written as the
/// object. A zoom outside 1…10 makes the file invalid.
public struct LockPhotoConfig: Codable, Equatable {
    public var path: String
    public var zoom: Double
    public var offsetX: Double
    public var offsetY: Double

    public init(path: String, zoom: Double = 1, offsetX: Double = 0, offsetY: Double = 0) {
        self.path = path
        self.zoom = zoom
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    private enum CodingKeys: String, CodingKey {
        case path, zoom
        case offsetX = "offset_x"
        case offsetY = "offset_y"
    }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let path = try? single.decode(String.self) {
            self.init(path: path)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let zoom = try c.decodeIfPresent(Double.self, forKey: .zoom) ?? 1
        let offsetX = try c.decodeIfPresent(Double.self, forKey: .offsetX) ?? 0
        let offsetY = try c.decodeIfPresent(Double.self, forKey: .offsetY) ?? 0
        guard (1...10).contains(zoom) else {
            throw DecodingError.dataCorruptedError(forKey: .zoom, in: c, debugDescription: "zoom must be between 1 and 10")
        }
        guard offsetX.isFinite, offsetY.isFinite else {
            throw DecodingError.dataCorruptedError(forKey: .offsetX, in: c, debugDescription: "offsets must be numbers")
        }
        self.init(path: try c.decode(String.self, forKey: .path), zoom: zoom, offsetX: offsetX, offsetY: offsetY)
    }
}

// MARK: - Strip blocks

public enum StripBlockType: String, Codable {
    case internet, load, volume, picture, empty
}

public struct StripBlockConfig: Codable, Equatable {
    public var type: StripBlockType
    public var action: String?          // run on a tap
    public var step: Int?               // the tap's step, for stepped actions (signed)
    public var icon: String?            // `picture` blocks
    public var host: String             // `internet` blocks
    public var arrowMs: Double          // `internet`: change that shows an arrow
    public var timeoutS: Double         // `internet`: no answer within this turns the block red
    /// `picture` blocks: how the app made `icon`, so it can edit it again. The agent ignores it and draws `icon`.
    public var tile: IconTile?

    /// The host an internet block pings when none is set, or an empty one is.
    public static let defaultHost = "one.one.one.one"

    public init(type: StripBlockType, action: String? = nil, step: Int? = nil, icon: String? = nil,
                host: String = defaultHost, arrowMs: Double = 2, timeoutS: Double = 3, tile: IconTile? = nil) {
        self.type = type
        self.action = action
        self.step = step
        self.icon = icon
        self.host = host
        self.arrowMs = arrowMs
        self.timeoutS = timeoutS
        self.tile = tile
    }

    private enum CodingKeys: String, CodingKey {
        case type, action, step, icon, host, tile
        case arrowMs = "arrow_ms"
        case timeoutS = "timeout_s"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(StripBlockType.self, forKey: .type)
        action = try c.decodeIfPresent(String.self, forKey: .action)
        step = try c.decodeIfPresent(Int.self, forKey: .step)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        // An empty host (a Host field emptied before BL-013's fix saved one) pings the default, as a missing one does.
        let host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        self.host = host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Self.defaultHost : host
        arrowMs = try c.decodeIfPresent(Double.self, forKey: .arrowMs) ?? 2
        timeoutS = try c.decodeIfPresent(Double.self, forKey: .timeoutS) ?? 3
        tile = (try? c.decodeIfPresent(IconTile.self, forKey: .tile)) ?? nil     // one that doesn't read: none
        // Refuse impossible numbers here, at load: the probe turns timeout_s into nanoseconds and
        // milliseconds with integer conversions that would crash on them.
        guard (0.1...60).contains(timeoutS) else {
            throw DecodingError.dataCorruptedError(forKey: .timeoutS, in: c,
                                                   debugDescription: "timeout_s must be between 0.1 and 60 seconds")
        }
        guard arrowMs >= 0 else {
            throw DecodingError.dataCorruptedError(forKey: .arrowMs, in: c,
                                                   debugDescription: "arrow_ms must be 0 or more")
        }
    }

    /// The internet settings are written only for `internet` blocks.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(action, forKey: .action)
        try c.encodeIfPresent(step, forKey: .step)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encodeIfPresent(tile, forKey: .tile)
        if type == .internet {
            try c.encode(host, forKey: .host)
            try c.encode(arrowMs, forKey: .arrowMs)
            try c.encode(timeoutS, forKey: .timeoutS)
        }
    }
}

// MARK: - Controls

public struct ButtonConfig: Codable, Equatable {
    public var action: String
    public var icon: String?
    public var step: Int?               // for stepped actions (volume, monitor brightness): signed, +5 up, -5 down
    /// How the app made `icon`, so it can edit it again. The agent ignores it and draws `icon`.
    public var tile: IconTile?

    public init(action: String, icon: String? = nil, step: Int? = nil, tile: IconTile? = nil) {
        self.action = action
        self.icon = icon
        self.step = step
        self.tile = tile
    }

    private enum CodingKeys: String, CodingKey { case action, icon, step, tile }

    /// A `tile` that doesn't read (a hand-edit typo, a kind from a newer app) reads as none: the key still loads, and
    /// so does the rest of the file.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        action = try c.decode(String.self, forKey: .action)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        step = try c.decodeIfPresent(Int.self, forKey: .step)
        tile = (try? c.decodeIfPresent(IconTile.self, forKey: .tile)) ?? nil
    }
}

/// A key icon the app generated: text on a colour, or a symbol from its library on a colour (`#RRGGBB`).
/// `foreground` nil: white or near-black, whichever reads on the background.
public struct IconTile: Codable, Equatable, Hashable {
    public enum Kind: String, Codable, Hashable { case text, symbol }

    public var kind: Kind
    public var text: String?
    public var symbol: String?
    public var style: String?           // "bold" or "fill" (symbols)
    public var background: String
    public var foreground: String?

    public init(kind: Kind, text: String?, symbol: String?, style: String?, background: String, foreground: String?) {
        self.kind = kind
        self.text = text
        self.symbol = symbol
        self.style = style
        self.background = background
        self.foreground = foreground
    }
}

/// A knob: a turn and a press, or (N4) a list. A list knob steps through its items as it turns; the strip block
/// above it shows the pick, and a press of the knob or a tap of the block runs it (docs/design/knob_lists.md).
/// Its `rotate` and `press` are `none` and never written.
public struct KnobConfig: Codable, Equatable {
    public var rotate: KnobAction
    public var press: KnobAction
    public var list: [ButtonConfig]?

    public init(rotate: KnobAction, press: KnobAction) {
        self.rotate = rotate
        self.press = press
        self.list = nil
    }

    public init(list: [ButtonConfig]) {
        self.rotate = KnobAction(action: "none")
        self.press = KnobAction(action: "none")
        self.list = list
    }

    private enum CodingKeys: String, CodingKey { case rotate, press, list }

    /// Either `list`, or both `rotate` and `press`: a list with a turn or a press, or a knob with neither, makes the
    /// file invalid.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let list = try c.decodeIfPresent([ButtonConfig].self, forKey: .list) {
            guard !c.contains(.rotate), !c.contains(.press) else {
                throw DecodingError.dataCorruptedError(forKey: .list, in: c,
                                                       debugDescription: "a knob has a list or a turn and a press, not both")
            }
            self.init(list: list)
        } else {
            self.init(rotate: try c.decode(KnobAction.self, forKey: .rotate),
                      press: try c.decode(KnobAction.self, forKey: .press))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let list {
            try c.encode(list, forKey: .list)
        } else {
            try c.encode(rotate, forKey: .rotate)
            try c.encode(press, forKey: .press)
        }
    }

    /// What New Preset copies from this knob: each half whose action is built in (volume, mute, monitor
    /// brightness, switch monitor, ZR7: `LockPolicy.builtIns`), the other as `none`. Nil for a list, or when
    /// neither half is built in (owner, 26/11/2026).
    public func builtInsOnly() -> KnobConfig? {
        guard list == nil else { return nil }
        func kept(_ half: KnobAction) -> KnobAction {
            LockPolicy.builtIns.contains(half.action) ? half : KnobAction(action: "none")
        }
        let copy = KnobConfig(rotate: kept(rotate), press: kept(press))
        return copy.rotate.action == "none" && copy.press.action == "none" ? nil : copy
    }
}

public struct KnobAction: Codable, Equatable {
    public var action: String
    public var step: Int?

    public init(action: String, step: Int? = nil) {
        self.action = action
        self.step = step
    }
}

public struct ActionConfig: Codable, Equatable {
    public var action: String
    public var step: Int?

    /// Makes the deck's next preset live (BL-033): the daemon hands it to the agent, which saves `active_preset`.
    public static let nextPreset = ActionConfig(action: "next_preset")

    public init(action: String, step: Int? = nil) {
        self.action = action
        self.step = step
    }
}
