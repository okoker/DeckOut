import Darwin
import Foundation

/// CPU tick counters since boot (all cores), from `host_statistics(HOST_CPU_LOAD_INFO)`.
struct CPUTicks: Equatable {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32
}

/// macOS memory pressure, as Activity Monitor's memory graph shows it.
enum PressureLevel: Equatable {
    case normal, warning, critical

    /// `kern.memorystatus_vm_pressure_level`: 2 warning, 4 critical, anything else normal (as Stats reads it).
    init(sysctlValue: Int32) {
        switch sysctlValue {
        case 2: self = .warning
        case 4: self = .critical
        default: self = .normal
        }
    }
}

/// CPU and memory figures for the load block. No child processes: one host call and two sysctls.
/// Both sysctls are readable without root but undocumented by Apple; a failed read gives nil ("–").
enum SystemLoad {
    private static let host = mach_host_self()

    static func readTicks() -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks   // CPU_STATE_USER, _SYSTEM, _IDLE, _NICE
        return CPUTicks(user: t.0, system: t.1, idle: t.2, nice: t.3)
    }

    /// Busy share between two readings: (Δuser + Δsystem) / Δtotal. Counters may wrap; nil if no time passed.
    static func cpuPercent(prev: CPUTicks, cur: CPUTicks) -> Int? {
        let user = Double(cur.user &- prev.user)
        let system = Double(cur.system &- prev.system)
        let idle = Double(cur.idle &- prev.idle)
        let nice = Double(cur.nice &- prev.nice)
        let total = user + system + idle + nice
        guard total > 0 else { return nil }
        return Int(((user + system) / total * 100).rounded())
    }

    /// Memory in use under macOS's own measure: 100 − `kern.memorystatus_level` (percent still available).
    static func memoryPercent() -> Int? {
        guard let available = sysctlInt("kern.memorystatus_level"), (0...100).contains(available) else { return nil }
        return 100 - Int(available)
    }

    static func pressureLevel() -> PressureLevel? {
        sysctlInt("kern.memorystatus_vm_pressure_level").map(PressureLevel.init(sysctlValue:))
    }

    private static func sysctlInt(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}

/// Traffic-light colour for one load figure.
enum LoadColour: Equatable {
    case green, amber, red

    /// CPU: green below 50 %, amber 50–79 %, red from 80 %.
    static func cpu(_ percent: Int) -> LoadColour {
        percent >= 80 ? .red : percent >= 50 ? .amber : .green
    }

    /// Memory follows macOS's own pressure level, not the percentage.
    static func memory(_ level: PressureLevel) -> LoadColour {
        switch level {
        case .normal: return .green
        case .warning: return .amber
        case .critical: return .red
        }
    }
}
