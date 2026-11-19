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
    let path = repoRoot.appendingPathComponent("config.example.json").path
    let config = try #require(DeckConfig.load(from: path))
    #expect(config.brightness == 50)
    #expect(config.buttons.count == 9)
    #expect(config.knobs.count == 3)
    #expect(config.displays?.count == 2)
}
