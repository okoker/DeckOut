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
    public var lockPhoto: String?
    public var presets: [N4Preset]
    /// The live preset's name. If no preset has it, the first preset is live.
    public var activePreset: String

    public init(brightness: Int, knobs: [String: KnobConfig], swipe: ActionConfig?, lockPhoto: String?,
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
        lockPhoto = try c.decodeIfPresent(String.self, forKey: .lockPhoto)
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

    public init(type: StripBlockType, action: String? = nil, step: Int? = nil, icon: String? = nil,
                host: String = "one.one.one.one", arrowMs: Double = 2, timeoutS: Double = 3) {
        self.type = type
        self.action = action
        self.step = step
        self.icon = icon
        self.host = host
        self.arrowMs = arrowMs
        self.timeoutS = timeoutS
    }

    private enum CodingKeys: String, CodingKey {
        case type, action, step, icon, host
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

    public init(action: String, icon: String? = nil, step: Int? = nil) {
        self.action = action
        self.icon = icon
        self.step = step
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
