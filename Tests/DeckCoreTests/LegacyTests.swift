import Foundation
import Testing
@testable import DeckCore

/// Pins the N3 behaviour as it was before N4 support, so the refactor can't change it silently.

@Test func n3ParserMatchesToday() {
    let n3 = DeckModel.n3
    #expect(n3.decode(ackReport(0x01, 1)) == .keyDown("lcd_1"))
    #expect(n3.decode(ackReport(0x25, 1)) == .keyDown("btn_1"))
    #expect(n3.decode(ackReport(0x51, 0)) == .knobTurn("big", +1))
    #expect(n3.decode(ackReport(0x90, 0)) == .knobTurn("small_1", -1))
    #expect(n3.decode(ackReport(0x34, 1)) == .knobDown("small_2"))

    var notAck = ackReport(0x01, 1)
    notAck[0] = 0x42
    #expect(n3.decode(notAck) == nil)

    #expect(n3.decode(Array(ackReport(0x01, 1).prefix(10))) == nil)
}

@Test func oldConfigParses() throws {
    // v1.0.0's config.example.json, frozen: a file with no `decks` key is the N3 section.
    let data = try Data(contentsOf: repoRoot.appendingPathComponent("Tests/DeckCoreTests/Fixtures/config-v1.0.0.json"))
    let config = try AppConfig.parse(data)
    let n3 = try #require(config.n3)
    #expect(n3.brightness == 50)
    #expect(n3.buttons.count == 9)
    #expect(n3.presets[0].knobs.count == 3)       // the deck's knobs, now in its one preset
    #expect(config.displays?.count == 2)
    #expect(config.n4 == nil)
}
