import Foundation

// The config file: shared settings at the top, one section per deck under `decks`.
//
//   { "displays": [...], "decks": { "n3": { ... }, "n4": { ... } } }
//
// Each deck section holds its presets (the keys, and on the N4 the strip) and names the live one in
// `active_preset`; knobs, brightness, the swipe and the lock photo belong to the deck. A section without
// `presets` (files from before presets) reads as one preset named "Default" made from its `keys` + `strip` (N4) or
// `buttons` (N3).
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

/// One N3 layout: the six LCD keys and three buttons.
public struct N3Preset: Codable, Equatable {
    public var name: String
    public var buttons: [String: ButtonConfig]

    public init(name: String, buttons: [String: ButtonConfig]) {
        self.name = name
        self.buttons = buttons
    }

    private enum CodingKeys: String, CodingKey { case name, buttons }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        buttons = try c.decodeIfPresent([String: ButtonConfig].self, forKey: .buttons) ?? [:]
    }
}

/// One N4 layout: the ten keys and the four strip blocks.
public struct N4Preset: Codable, Equatable {
    public var name: String
    public var keys: [String: ButtonConfig]
    public var strip: [String: StripBlockConfig]

    public init(name: String, keys: [String: ButtonConfig], strip: [String: StripBlockConfig]) {
        self.name = name
        self.keys = keys
        self.strip = strip
    }

    private enum CodingKeys: String, CodingKey { case name, keys, strip }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        keys = try c.decodeIfPresent([String: ButtonConfig].self, forKey: .keys) ?? [:]
        strip = try c.decodeIfPresent([String: StripBlockConfig].self, forKey: .strip) ?? [:]
    }
}

// MARK: - Deck sections

/// TreasLin N3. Keys `lcd_1`–`lcd_6`, `btn_1`–`btn_3`; knobs `big`, `small_1`, `small_2`.
public struct N3Section: Codable, Equatable {
    public var brightness: Int
    public var knobs: [String: KnobConfig]
    public var presets: [N3Preset]
    /// The live preset's name. If no preset has it, the first preset is live.
    public var activePreset: String

    public init(brightness: Int, knobs: [String: KnobConfig], presets: [N3Preset], activePreset: String) {
        self.brightness = brightness
        self.knobs = knobs
        self.presets = presets
        self.activePreset = activePreset
    }

    /// The live preset: the one named `activePreset`, else the first.
    public var active: N3Preset {
        presets.first { $0.name == activePreset } ?? presets.first ?? N3Preset(name: "Default", buttons: [:])
    }

    public var buttons: [String: ButtonConfig] { active.buttons }

    private enum CodingKeys: String, CodingKey {
        case brightness, knobs, buttons, presets
        case activePreset = "active_preset"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        brightness = try c.decode(Int.self, forKey: .brightness)
        knobs = try c.decode([String: KnobConfig].self, forKey: .knobs)
        if let presets = try c.decodeIfPresent([N3Preset].self, forKey: .presets) {
            try checkPresetNames(presets.map(\.name), in: c, key: .presets)
            self.presets = presets
            activePreset = try c.decodeIfPresent(String.self, forKey: .activePreset) ?? presets[0].name
        } else {
            // Before presets, `buttons` was required, as it still is in this form.
            presets = [N3Preset(name: "Default", buttons: try c.decode([String: ButtonConfig].self, forKey: .buttons))]
            activePreset = "Default"
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(brightness, forKey: .brightness)
        try c.encode(knobs, forKey: .knobs)
        try c.encode(presets, forKey: .presets)
        try c.encode(activePreset, forKey: .activePreset)
    }
}

/// MiraBox N4. Keys `key_1`–`key_5` (top row), `key_6`–`key_10` (bottom row); knobs `knob_1`–`knob_4`
/// left → right; strip blocks `"1"`–`"4"` left → right.
public struct N4Section: Codable, Equatable {
    public var brightness: Int
    public var knobs: [String: KnobConfig]
    public var swipe: ActionConfig?
    public var lockPhoto: LockPhotoConfig?
    public var presets: [N4Preset]
    /// The live preset's name. If no preset has it, the first preset is live.
    public var activePreset: String

    public init(brightness: Int, knobs: [String: KnobConfig], swipe: ActionConfig?, lockPhoto: LockPhotoConfig?,
                presets: [N4Preset], activePreset: String) {
        self.brightness = brightness
        self.knobs = knobs
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

    private enum CodingKeys: String, CodingKey {
        case brightness, keys, knobs, strip, swipe, presets
        case lockPhoto = "lock_photo"
        case activePreset = "active_preset"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        brightness = try c.decode(Int.self, forKey: .brightness)
        knobs = try c.decodeIfPresent([String: KnobConfig].self, forKey: .knobs) ?? [:]
        swipe = try c.decodeIfPresent(ActionConfig.self, forKey: .swipe)
        lockPhoto = try c.decodeIfPresent(LockPhotoConfig.self, forKey: .lockPhoto)
        if let presets = try c.decodeIfPresent([N4Preset].self, forKey: .presets) {
            try checkPresetNames(presets.map(\.name), in: c, key: .presets)
            self.presets = presets
            activePreset = try c.decodeIfPresent(String.self, forKey: .activePreset) ?? presets[0].name
        } else {
            presets = [N4Preset(name: "Default",
                                keys: try c.decodeIfPresent([String: ButtonConfig].self, forKey: .keys) ?? [:],
                                strip: try c.decodeIfPresent([String: StripBlockConfig].self, forKey: .strip) ?? [:])]
            activePreset = "Default"
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(brightness, forKey: .brightness)
        try c.encode(knobs, forKey: .knobs)
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

    public init(type: StripBlockType, action: String? = nil, step: Int? = nil, icon: String? = nil,
                host: String = "one.one.one.one", arrowMs: Double = 2, timeoutS: Double = 3, tile: IconTile? = nil) {
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
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? "one.one.one.one"
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

public struct KnobConfig: Codable, Equatable {
    public var rotate: KnobAction
    public var press: KnobAction

    public init(rotate: KnobAction, press: KnobAction) {
        self.rotate = rotate
        self.press = press
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

    public init(action: String, step: Int? = nil) {
        self.action = action
        self.step = step
    }
}
