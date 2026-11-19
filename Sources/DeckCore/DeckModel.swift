// Supported deck models. Each deck's input is decoded with its own map: the N3 and the N4
// reuse many event codes with different meanings (e.g. 0x50 is the N3 big knob, the N4 knob 2).

public enum DeckKind: String {
    case n3, n4
}

/// One input from a deck. The strings are the control's config keys
/// (`lcd_1`, `btn_1`, `big` on the N3; `key_1`, `knob_1`, strip block `"1"` on the N4).
public enum DeckInput: Equatable {
    case keyDown(String)
    case keyUp(String)
    case knobTurn(String, Int)      // +1 clockwise, -1 anticlockwise
    case knobDown(String)
    case knobUp(String)
    case stripTap(String)
    case swipe
}

public struct DeckModel {
    public let kind: DeckKind
    public let vendorID: Int
    public let productID: Int
    public let usagePage: Int = 0xFFA0
    public let usage: Int = 0x0001
    /// Config key → wire slot (the key byte in a `BAT` header).
    public let keySlots: [String: UInt8]
    public let stripSlots: [String: UInt8]

    // Event code (report byte 9) → control.
    private let keys: [UInt8: String]               // state 1 press, 0 release
    private let knobPresses: [UInt8: String]        // state 1 press, 0 release
    private let knobTurns: [UInt8: (String, Int)]   // state ignored
    private let stripTaps: [UInt8: String]          // state ignored
    private let swipeCode: UInt8?

    /// Decode a raw input report (no report-ID byte): "ACK\0\0OK\0\0", code at byte 9, state at byte 10.
    /// Returns nil for anything this model doesn't define.
    public func decode(_ report: [UInt8]) -> DeckInput? {
        guard report.count >= 11, report[0] == 0x41, report[1] == 0x43, report[2] == 0x4B else { return nil }
        let code = report[9]
        let state = report[10]

        if let key = keys[code] {
            switch state {
            case 0x01: return .keyDown(key)
            case 0x00: return .keyUp(key)
            default:   return nil
            }
        }
        if let knob = knobPresses[code] {
            switch state {
            case 0x01: return .knobDown(knob)
            case 0x00: return .knobUp(knob)
            default:   return nil
            }
        }
        if let turn = knobTurns[code] { return .knobTurn(turn.0, turn.1) }
        if let block = stripTaps[code] { return .stripTap(block) }
        if let swipeCode, code == swipeCode { return .swipe }
        return nil
    }

    // MARK: - Models

    /// TreasLin N3: 6 LCD keys, 3 side buttons, 3 knobs.
    public static let n3 = DeckModel(
        kind: .n3, vendorID: 0x5548, productID: 0x1001,
        keySlots: ["lcd_1": 1, "lcd_2": 2, "lcd_3": 3, "lcd_4": 4, "lcd_5": 5, "lcd_6": 6],
        stripSlots: [:],
        keys: [
            0x01: "lcd_1", 0x02: "lcd_2", 0x03: "lcd_3", 0x04: "lcd_4", 0x05: "lcd_5", 0x06: "lcd_6",
            0x25: "btn_1", 0x30: "btn_2", 0x31: "btn_3",
        ],
        knobPresses: [0x35: "big", 0x33: "small_1", 0x34: "small_2"],
        knobTurns: [
            0x50: ("big", -1), 0x51: ("big", +1),
            0x90: ("small_1", -1), 0x91: ("small_1", +1),
            0x60: ("small_2", -1), 0x61: ("small_2", +1),
        ],
        stripTaps: [:],
        swipeCode: nil
    )

    /// MiraBox Stream Dock N4: 10 LCD keys (2 rows of 5), a touch strip of 4 image blocks, 4 push-knobs.
    /// Maps verified on the unit 18/11/2026 (`docs/design/n4_support.md`).
    public static let n4 = DeckModel(
        kind: .n4, vendorID: 0x6602, productID: 0x1001,
        keySlots: [
            "key_1": 11, "key_2": 12, "key_3": 13, "key_4": 14, "key_5": 15,   // top row
            "key_6": 6, "key_7": 7, "key_8": 8, "key_9": 9, "key_10": 10,      // bottom row
        ],
        stripSlots: ["1": 1, "2": 2, "3": 3, "4": 4],
        keys: [
            0x01: "key_1", 0x02: "key_2", 0x03: "key_3", 0x04: "key_4", 0x05: "key_5",
            0x06: "key_6", 0x07: "key_7", 0x08: "key_8", 0x09: "key_9", 0x0A: "key_10",
        ],
        knobPresses: [0x37: "knob_1", 0x35: "knob_2", 0x33: "knob_3", 0x36: "knob_4"],
        knobTurns: [
            0xA0: ("knob_1", -1), 0xA1: ("knob_1", +1),
            0x50: ("knob_2", -1), 0x51: ("knob_2", +1),
            0x90: ("knob_3", -1), 0x91: ("knob_3", +1),
            0x70: ("knob_4", -1), 0x71: ("knob_4", +1),
        ],
        stripTaps: [0x40: "1", 0x41: "2", 0x42: "3", 0x43: "4"],
        swipeCode: 0x39   // 0x38 (touch outside the blocks) is deliberately not a swipe
    )

    public static let all: [DeckModel] = [.n3, .n4]
}
