// CRT packet builders, shared by the N3 and the N4 (same protocol v3).
// Device identities and input maps live in DeckModel.swift.

enum Deck {
    static let packetSize: Int = 1025   // 1 byte report ID + 1024 data
}

// MARK: - Packet builders

enum CRTCommand {

    // Private helper: builds the full 1025-byte packet.
    // Layout: [0x00] [CRT\0\0] [cmd bytes...] [zero-pad to 1025]
    private static func makePacket(cmd: [UInt8]) -> [UInt8] {
        let header: [UInt8] = [0x00,           // report ID
                               0x43, 0x52, 0x54, 0x00, 0x00]  // "CRT\0\0"
        var packet = header + cmd
        if packet.count < Deck.packetSize {
            packet += [UInt8](repeating: 0x00, count: Deck.packetSize - packet.count)
        }
        return packet
    }

    /// Wake / display-on command (DIS)
    static func makeDIS() -> [UInt8] {
        makePacket(cmd: [0x44, 0x49, 0x53])
    }

    /// Set brightness (LIG)
    static func makeLIG(_ brightness: UInt8) -> [UInt8] {
        makePacket(cmd: [0x4C, 0x49, 0x47, 0x00, 0x00, brightness])
    }

    /// Refresh / commit frame (STP)
    static func makeSTP() -> [UInt8] {
        makePacket(cmd: [0x53, 0x54, 0x50])
    }

    /// Clear all LCD regions (CLE)
    static func makeCLE() -> [UInt8] {
        makePacket(cmd: [0x43, 0x4C, 0x45, 0x00, 0x00, 0x00, 0xFF])
    }

    /// Keepalive (CONNECT)
    static func makeCONNECT() -> [UInt8] {
        makePacket(cmd: [0x43, 0x4F, 0x4E, 0x4E, 0x45, 0x43, 0x54])
    }

    /// BAT image header — begins image transfer for a key (0-indexed input, sent as 1-indexed)
    static func makeBAT(imageLength: Int, keyIndex: Int) -> [UInt8] {
        let lenHi = UInt8((imageLength >> 8) & 0xFF)
        let lenLo = UInt8(imageLength & 0xFF)
        let key = UInt8(keyIndex + 1)  // protocol uses 1-indexed keys
        return makePacket(cmd: [0x42, 0x41, 0x54, 0x00, 0x00, lenHi, lenLo, key])
    }

    /// Raw image data chunk — no CRT prefix, just report ID + payload
    static func makeDataChunk(data: [UInt8]) -> [UInt8] {
        var packet = [UInt8(0x00)] + data
        if packet.count < Deck.packetSize {
            packet += [UInt8](repeating: 0x00, count: Deck.packetSize - packet.count)
        }
        return packet
    }
}
