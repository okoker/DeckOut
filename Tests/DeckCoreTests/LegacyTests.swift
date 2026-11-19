import Foundation
import Testing
@testable import DeckCore

/// Pins the N3 behaviour as it was before N4 support, so the refactor can't change it silently.

/// An N3 input report: "ACK\0\0OK\0\0", then the event code (byte 9) and state (byte 10).
private func report(_ code: UInt8, _ state: UInt8) -> [UInt8] {
    [0x41, 0x43, 0x4B, 0x00, 0x00, 0x4F, 0x4B, 0x00, 0x00, code, state]
}

/// Spells a parsed event out by hand, so expectations are plain literals.
private func describe(_ event: DeckEvent?) -> String {
    switch event {
    case .buttonPress(let b)?:   return "buttonPress \(b.rawValue)"
    case .buttonRelease(let b)?: return "buttonRelease \(b.rawValue)"
    case .knobRotateCW(let k)?:  return "knobRotateCW \(k.rawValue)"
    case .knobRotateCCW(let k)?: return "knobRotateCCW \(k.rawValue)"
    case .knobPress(let k)?:     return "knobPress \(k.rawValue)"
    case .knobRelease(let k)?:   return "knobRelease \(k.rawValue)"
    case nil:                    return "nil"
    }
}

/// Repository root, found from this file's location (Tests/DeckCoreTests/LegacyTests.swift).
let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@Test func n3ParserMatchesToday() {
    #expect(describe(DeckEventParser.parse(data: report(0x01, 1))) == "buttonPress lcd1")
    #expect(describe(DeckEventParser.parse(data: report(0x25, 1))) == "buttonPress btn1")
    #expect(describe(DeckEventParser.parse(data: report(0x51, 0))) == "knobRotateCW big")
    #expect(describe(DeckEventParser.parse(data: report(0x90, 0))) == "knobRotateCCW small1")
    #expect(describe(DeckEventParser.parse(data: report(0x34, 1))) == "knobPress small2")

    var notAck = report(0x01, 1)
    notAck[0] = 0x42
    #expect(describe(DeckEventParser.parse(data: notAck)) == "nil")

    #expect(describe(DeckEventParser.parse(data: Array(report(0x01, 1).prefix(10)))) == "nil")
}

@Test func oldConfigParses() throws {
    let path = repoRoot.appendingPathComponent("config.example.json").path
    let config = try #require(DeckConfig.load(from: path))
    #expect(config.brightness == 50)
    #expect(config.buttons.count == 9)
    #expect(config.knobs.count == 3)
    #expect(config.displays?.count == 2)
}
