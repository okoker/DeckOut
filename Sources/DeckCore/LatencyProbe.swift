import Darwin
import Foundation

/// Arrow on the internet block: latency rose or fell by at least the threshold since the last reading.
enum Trend: Equatable {
    case up, down, none

    static func from(previous: Double?, current: Double, thresholdMs: Double) -> Trend {
        guard let previous else { return .none }
        let change = current - previous
        if change >= thresholdMs { return .up }
        if -change >= thresholdMs { return .down }
        return .none
    }
}

/// ICMP echo packets, as Apple's `ping` sends them when not root.
enum ICMP {
    /// Echo request: type 8, code 0, checksum, identifier, sequence (network byte order), 8 zero bytes.
    static func echoRequest(id: UInt16, seq: UInt16) -> [UInt8] {
        var packet: [UInt8] = [8, 0, 0, 0, UInt8(id >> 8), UInt8(id & 0xFF), UInt8(seq >> 8), UInt8(seq & 0xFF)]
        packet += [UInt8](repeating: 0, count: 8)
        let sum = checksum(packet)
        packet[2] = UInt8(sum >> 8)
        packet[3] = UInt8(sum & 0xFF)
        return packet
    }

    /// Internet checksum: one's complement of the one's-complement sum of 16-bit words.
    static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < bytes.count {
            sum += UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1])
            i += 2
        }
        if i < bytes.count { sum += UInt32(bytes[i]) << 8 }
        while sum > 0xFFFF { sum = (sum & 0xFFFF) + (sum >> 16) }
        return ~UInt16(sum)
    }

    /// True for an echo reply to our identifier and sequence. Skips an IPv4 header if present (macOS
    /// includes it on these sockets). The kernel hands every ICMP reply to every ICMP socket, so
    /// anything else — other programs' pings, late replies to an older sequence — is ignored.
    static func isReply(_ bytes: [UInt8], id: UInt16, seq: UInt16) -> Bool {
        var start = 0
        if let first = bytes.first, first >> 4 == 4 { start = Int(first & 0x0F) * 4 }
        guard start >= 0, bytes.count >= start + 8 else { return false }
        return bytes[start] == 0 && bytes[start + 1] == 0
            && bytes[start + 4] == UInt8(id >> 8) && bytes[start + 5] == UInt8(id & 0xFF)
            && bytes[start + 6] == UInt8(seq >> 8) && bytes[start + 7] == UInt8(seq & 0xFF)
    }
}

/// Measures internet latency: looks the host up through the system resolver (IPv4 only — also proves
/// DNS works), then sends one ICMP echo over an unprivileged SOCK_DGRAM / IPPROTO_ICMP socket kept open
/// between readings. Both calls block, so they run on the probe's own serial queue. No child process.
final class LatencyProbe {
    let host: String
    let timeout: TimeInterval

    private let queue = DispatchQueue(label: "streamdeck.latency", qos: .utility)
    private let identifier = UInt16.random(in: 1...UInt16.max)
    // Used on `queue` only:
    private var socketFD: Int32 = -1
    private var sequence: UInt16 = 0

    init(host: String, timeout: TimeInterval) {
        self.host = host
        self.timeout = timeout
    }

    deinit {
        if socketFD >= 0 { close(socketFD) }
    }

    /// One reading. `done` runs on the main thread with the echo round trip in ms, or nil when the
    /// lookup failed or no reply came within `timeout`.
    func measure(_ done: @escaping (Double?) -> Void) {
        queue.async { [self] in
            let ms = measureNow()
            DispatchQueue.main.async { done(ms) }
        }
    }

    // MARK: - Queue only

    private func measureNow() -> Double? {
        let lookupStart = DispatchTime.now().uptimeNanoseconds
        guard var address = resolve() else { return nil }
        let lookupMs = Double(DispatchTime.now().uptimeNanoseconds - lookupStart) / 1e6
        if lookupMs > 1000 { print("Internet: looking up \(host) took \(Int(lookupMs)) ms") }

        if socketFD < 0 {
            socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
            guard socketFD >= 0 else {
                print("Internet: could not open an ICMP socket (errno \(errno))")
                return nil
            }
        }

        sequence &+= 1
        let packet = ICMP.echoRequest(id: identifier, seq: sequence)
        let sentAt = DispatchTime.now().uptimeNanoseconds
        let sent = packet.withUnsafeBytes { bytes in
            withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(socketFD, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == packet.count else {
            closeSocket()       // e.g. no network: start clean next time
            return nil
        }

        let deadline = sentAt + UInt64(timeout * 1e9)
        var buffer = [UInt8](repeating: 0, count: 1500)
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { return nil }
            var pfd = pollfd(fd: socketFD, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, Int32((deadline - now) / 1_000_000) + 1)
            if ready == 0 { return nil }
            if ready < 0 {
                if errno == EINTR { continue }
                closeSocket()
                return nil
            }
            let count = recv(socketFD, &buffer, buffer.count, 0)
            if count < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                closeSocket()
                return nil
            }
            if ICMP.isReply(Array(buffer[0..<count]), id: identifier, seq: sequence) {
                return Double(DispatchTime.now().uptimeNanoseconds - sentAt) / 1e6
            }
        }
    }

    private func resolve() -> sockaddr_in? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return nil }
        defer { freeaddrinfo(result) }
        guard first.pointee.ai_family == AF_INET, let sa = first.pointee.ai_addr else { return nil }
        return sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
    }

    private func closeSocket() {
        if socketFD >= 0 { close(socketFD) }
        socketFD = -1
    }
}
