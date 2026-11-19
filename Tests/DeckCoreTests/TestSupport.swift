import Foundation

/// A deck input report as macOS delivers it (no report-ID byte):
/// "ACK\0\0OK\0\0", then the event code (byte 9) and state (byte 10).
func ackReport(_ code: UInt8, _ state: UInt8) -> [UInt8] {
    [0x41, 0x43, 0x4B, 0x00, 0x00, 0x4F, 0x4B, 0x00, 0x00, code, state]
}

/// Repository root, found from this file's location (Tests/DeckCoreTests/TestSupport.swift).
let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
