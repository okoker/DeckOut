import Foundation

// The config file: shared settings at the top, one section per deck under `decks`.
//
//   { "displays": [...], "decks": { "n3": { ... }, "n4": { ... } } }
//
// Old (v1.0.0) format: a file with no `decks` key is the N3 section itself
// (top-level `brightness`, `buttons`, `knobs`). When `decks` is present, those
// top-level keys are ignored.

public struct AppConfig {
    public let displays: [DisplayConfig]?
    public let n3: N3Section?
    public let n4: N4Section?

    public static func parse(_ data: Data) throws -> AppConfig {
        try JSONDecoder().decode(AppConfig.self, from: data)
    }

    /// Read and parse the file at `path`. Prints the reason and returns nil on failure.
    public static func load(from path: String) -> AppConfig? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            print("Error: config file not found at \(path)")
            return nil
        }
        do {
            return try parse(data)
        } catch {
            print("Error: failed to parse config at \(path): \(error)")
            return nil
        }
    }
}

extension AppConfig: Decodable {
    private enum CodingKeys: String, CodingKey { case displays, decks }

    private struct Decks: Decodable {
        let n3: N3Section?
        let n4: N4Section?
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
}

public struct DisplayConfig: Codable, Equatable {
    public let name: String
    public let serial: String          // AN Serial from `m1ddc display list detailed`

    public init(name: String, serial: String) {
        self.name = name
        self.serial = serial
    }
}

// MARK: - Deck sections

/// TreasLin N3. Keys `lcd_1`–`lcd_6`, `btn_1`–`btn_3`; knobs `big`, `small_1`, `small_2`.
public struct N3Section: Decodable {
    public let brightness: Int
    public let buttons: [String: ButtonConfig]
    public let knobs: [String: KnobConfig]
}

/// MiraBox N4. Keys `key_1`–`key_5` (top row), `key_6`–`key_10` (bottom row); knobs `knob_1`–`knob_4`
/// left → right; strip blocks `"1"`–`"4"` left → right.
public struct N4Section: Decodable {
    public let brightness: Int
    public let keys: [String: ButtonConfig]
    public let knobs: [String: KnobConfig]
    public let strip: [String: StripBlockConfig]
    public let swipe: ActionConfig?
    public let lockPhoto: String?

    private enum CodingKeys: String, CodingKey {
        case brightness, keys, knobs, strip, swipe
        case lockPhoto = "lock_photo"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        brightness = try c.decode(Int.self, forKey: .brightness)
        keys = try c.decodeIfPresent([String: ButtonConfig].self, forKey: .keys) ?? [:]
        knobs = try c.decodeIfPresent([String: KnobConfig].self, forKey: .knobs) ?? [:]
        strip = try c.decodeIfPresent([String: StripBlockConfig].self, forKey: .strip) ?? [:]
        swipe = try c.decodeIfPresent(ActionConfig.self, forKey: .swipe)
        lockPhoto = try c.decodeIfPresent(String.self, forKey: .lockPhoto)
    }
}

// MARK: - Strip blocks

public enum StripBlockType: String, Decodable {
    case internet, load, volume, picture, empty
}

public struct StripBlockConfig: Decodable {
    public let type: StripBlockType
    public let action: String?          // run on a tap
    public let icon: String?            // `picture` blocks
    public let host: String             // `internet` blocks
    public let arrowMs: Double          // `internet`: change that shows an arrow
    public let timeoutS: Double         // `internet`: no answer within this turns the block red

    private enum CodingKeys: String, CodingKey {
        case type, action, icon, host
        case arrowMs = "arrow_ms"
        case timeoutS = "timeout_s"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(StripBlockType.self, forKey: .type)
        action = try c.decodeIfPresent(String.self, forKey: .action)
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
}

// MARK: - Controls

public struct ButtonConfig: Codable {
    public let action: String
    public let icon: String?
}

public struct KnobConfig: Codable {
    public let rotate: KnobAction
    public let press: KnobAction
}

public struct KnobAction: Codable {
    public let action: String
    public let step: Int?
}

public struct ActionConfig: Decodable {
    public let action: String
}
