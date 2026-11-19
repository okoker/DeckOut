import Foundation
import Testing
@testable import DeckCore

// MARK: - Trend arrow

@Test func trendFollowsThreshold() {
    #expect(Trend.from(previous: 10, current: 12, thresholdMs: 2) == .up)
    #expect(Trend.from(previous: 10, current: 11.9, thresholdMs: 2) == .none)
    #expect(Trend.from(previous: 10, current: 8, thresholdMs: 2) == .down)
    #expect(Trend.from(previous: 10, current: 8.1, thresholdMs: 2) == .none)
    #expect(Trend.from(previous: nil, current: 50, thresholdMs: 2) == .none)
}

// MARK: - ICMP packets

@Test func echoRequestLayoutAndChecksum() {
    let p = ICMP.echoRequest(id: 0x1234, seq: 1)
    // type 8, code 0, checksum, identifier, sequence (network byte order), 8 zero bytes of payload
    // checksum by hand: ~(0x0800 + 0x1234 + 0x0001) = ~0x1A35 = 0xE5CA
    #expect(p == [0x08, 0x00, 0xE5, 0xCA, 0x12, 0x34, 0x00, 0x01, 0, 0, 0, 0, 0, 0, 0, 0])
}

@Test func echoRequestChecksumFoldsToAllOnes() {
    let p = ICMP.echoRequest(id: 0xBEEF, seq: 0xFFFF)
    var sum: UInt32 = 0
    for i in stride(from: 0, to: p.count, by: 2) { sum += UInt32(p[i]) << 8 | UInt32(p[i + 1]) }
    while sum > 0xFFFF { sum = (sum & 0xFFFF) + (sum >> 16) }
    #expect(sum == 0xFFFF)
}

private let reply: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x12, 0x34, 0x00, 0x07, 0, 0, 0, 0, 0, 0, 0, 0]
private let ipv4Header: [UInt8] = [0x45, 0, 0, 36, 0, 0, 0, 0, 64, 1, 0, 0, 1, 1, 1, 1, 10, 0, 0, 2]

@Test func replyMatchesWithOrWithoutIPHeader() {
    #expect(ICMP.isReply(reply, id: 0x1234, seq: 7))
    #expect(ICMP.isReply(ipv4Header + reply, id: 0x1234, seq: 7))
}

@Test func replyForSomeoneElseDoesNotMatch() {
    // The kernel hands every ICMP reply to every ICMP socket: match on identifier and sequence.
    #expect(!ICMP.isReply(reply, id: 0x1235, seq: 7))
    #expect(!ICMP.isReply(reply, id: 0x1234, seq: 8))
    var request = reply
    request[0] = 8                                   // an echo request, not a reply
    #expect(!ICMP.isReply(request, id: 0x1234, seq: 7))
    #expect(!ICMP.isReply(Array(reply.prefix(6)), id: 0x1234, seq: 7))
    #expect(!ICMP.isReply(Array(ipv4Header.prefix(12)), id: 0x1234, seq: 7))
}

// MARK: - Block image

@Test func internetRendersAllStates() throws {
    for (ms, trend, failed) in [(14.2, Trend.up, false), (4.0, .down, false), (120.0, .none, false), (nil, .none, false), (nil, .none, true)] as [(Double?, Trend, Bool)] {
        let img = try decodeImage(StripRenderer.internet(ms: ms, trend: trend, failed: failed))
        #expect(img.width == 176 && img.height == 112)
    }
}

@Test func failedBlockIsRed() throws {
    let img = try decodeImage(StripRenderer.internet(ms: nil, trend: .none, failed: true))
    let corner = pixel(img, 4, 4)
    #expect(corner.r > 150 && corner.g < 80 && corner.b < 80)
    let ok = pixel(try decodeImage(StripRenderer.internet(ms: 14, trend: .none, failed: false)), 4, 4)
    #expect(ok.r < 30)
}
