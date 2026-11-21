import Testing
@testable import DeckCore

/// Each deck's events are decoded with that deck's own map (design: "Deck models").

@Test func modelsMatchOnlyTheTwoDecks() {
    #expect(DeckModel.all.map(\.kind) == [.n3, .n4])
    #expect(DeckModel.n3.vendorID == 0x5548 && DeckModel.n3.productID == 0x1001)
    #expect(DeckModel.n4.vendorID == 0x6602 && DeckModel.n4.productID == 0x1001)
    #expect(DeckModel.all.allSatisfy { $0.usagePage == 0xFFA0 && $0.usage == 0x0001 })
}

@Test func n3Table() {
    let m = DeckModel.n3
    let keys: [(UInt8, String)] = [
        (0x01, "lcd_1"), (0x02, "lcd_2"), (0x03, "lcd_3"), (0x04, "lcd_4"), (0x05, "lcd_5"), (0x06, "lcd_6"),
        (0x25, "btn_1"), (0x30, "btn_2"), (0x31, "btn_3"),
    ]
    for (code, name) in keys {
        #expect(m.decode(ackReport(code, 1)) == .keyDown(name))
        #expect(m.decode(ackReport(code, 0)) == .keyUp(name))
        #expect(m.decode(ackReport(code, 2)) == nil)
    }
    let turns: [(UInt8, String, Int)] = [
        (0x51, "big", +1), (0x50, "big", -1),
        (0x91, "small_1", +1), (0x90, "small_1", -1),
        (0x61, "small_2", +1), (0x60, "small_2", -1),
    ]
    for (code, name, sign) in turns {
        #expect(m.decode(ackReport(code, 0)) == .knobTurn(name, sign))
    }
    let presses: [(UInt8, String)] = [(0x35, "big"), (0x33, "small_1"), (0x34, "small_2")]
    for (code, name) in presses {
        #expect(m.decode(ackReport(code, 1)) == .knobDown(name))
        #expect(m.decode(ackReport(code, 0)) == .knobUp(name))
    }
    // N4-only codes mean nothing on the N3.
    for code: UInt8 in [0x07, 0x0A, 0x40, 0x39, 0x38, 0xA1, 0x37] {
        #expect(m.decode(ackReport(code, 0)) == nil)
        #expect(m.decode(ackReport(code, 1)) == nil)
    }
}

@Test func n4Table() {
    let m = DeckModel.n4
    for i in 1...10 {
        #expect(m.decode(ackReport(UInt8(i), 1)) == .keyDown("key_\(i)"))
        #expect(m.decode(ackReport(UInt8(i), 0)) == .keyUp("key_\(i)"))
    }
    #expect(m.decode(ackReport(0x01, 1)) == .keyDown("key_1"))
    #expect(m.decode(ackReport(0x0A, 0)) == .keyUp("key_10"))

    let turns: [(UInt8, String, Int)] = [
        (0xA1, "knob_1", +1), (0xA0, "knob_1", -1),
        (0x51, "knob_2", +1), (0x50, "knob_2", -1),
        (0x91, "knob_3", +1), (0x90, "knob_3", -1),
        (0x71, "knob_4", +1), (0x70, "knob_4", -1),
    ]
    for (code, name, sign) in turns {
        #expect(m.decode(ackReport(code, 0)) == .knobTurn(name, sign))
    }
    let presses: [(UInt8, String)] = [(0x37, "knob_1"), (0x35, "knob_2"), (0x33, "knob_3"), (0x36, "knob_4")]
    for (code, name) in presses {
        #expect(m.decode(ackReport(code, 1)) == .knobDown(name))
    }

    #expect(m.decode(ackReport(0x40, 0)) == .stripTap("1"))
    #expect(m.decode(ackReport(0x41, 0)) == .stripTap("2"))
    #expect(m.decode(ackReport(0x42, 0)) == .stripTap("3"))
    #expect(m.decode(ackReport(0x43, 0)) == .stripTap("4"))
    #expect(m.decode(ackReport(0x39, 0)) == .swipe)
    // Most swipes on the owner's unit come as 0x38, which a tap between two blocks also sends (21/11/2026).
    #expect(m.decode(ackReport(0x38, 0)) == .swipe)

    // N3-only codes mean nothing on the N4.
    for code: UInt8 in [0x25, 0x30, 0x31, 0x34, 0x60, 0x61] {
        #expect(m.decode(ackReport(code, 0)) == nil)
        #expect(m.decode(ackReport(code, 1)) == nil)
    }
}

@Test func overlappingCodesDecodePerDeck() {
    #expect(DeckModel.n3.decode(ackReport(0x50, 0)) == .knobTurn("big", -1))
    #expect(DeckModel.n4.decode(ackReport(0x50, 0)) == .knobTurn("knob_2", -1))
    #expect(DeckModel.n3.decode(ackReport(0x33, 1)) == .knobDown("small_1"))
    #expect(DeckModel.n4.decode(ackReport(0x33, 1)) == .knobDown("knob_3"))
    #expect(DeckModel.n3.decode(ackReport(0x06, 1)) == .keyDown("lcd_6"))
    #expect(DeckModel.n4.decode(ackReport(0x06, 1)) == .keyDown("key_6"))
}

@Test func malformedReportsDecodeToNothing() {
    for m in DeckModel.all {
        var notAck = ackReport(0x01, 1)
        notAck[0] = 0x42
        #expect(m.decode(notAck) == nil)
        #expect(m.decode(Array(ackReport(0x01, 1).prefix(10))) == nil)
        #expect(m.decode([]) == nil)
    }
}

@Test func slots() {
    let n4 = DeckModel.n4
    #expect(n4.keySlots["key_1"] == 11)
    #expect(n4.keySlots["key_5"] == 15)
    #expect(n4.keySlots["key_6"] == 6)
    #expect(n4.keySlots["key_10"] == 10)
    #expect(n4.keySlots.count == 10)
    #expect(n4.stripSlots["1"] == 1)
    #expect(n4.stripSlots["4"] == 4)
    #expect(n4.stripSlots.count == 4)

    let n3 = DeckModel.n3
    #expect(n3.keySlots["lcd_1"] == 1)
    #expect(n3.keySlots["lcd_6"] == 6)
    #expect(n3.keySlots.count == 6)       // side buttons have no screen
    #expect(n3.keySlots["btn_1"] == nil)
    #expect(n3.stripSlots.isEmpty)
}
