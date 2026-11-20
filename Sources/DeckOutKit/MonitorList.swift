import AppKit
import Foundation

/// An external monitor as `m1ddc` lists it.
public struct Monitor: Equatable, Identifiable, Hashable {
    public let number: Int          // m1ddc's index
    public let name: String         // product name
    public let serial: String       // AN serial: what `displays` stores
    public let displayID: UInt32    // the screen's CGDirectDisplayID
    public var id: String { serial }
}

/// The monitors the brightness keys can set, and where each sits, so two of the same model can be told apart.
public enum MonitorList {

    /// `m1ddc display list detailed` → monitors; one without an AN serial can't be named and is left out.
    public static func parse(_ output: String) -> [Monitor] {
        var monitors: [Monitor] = []
        var number: Int?, name: String?, serial: String?, displayID: UInt32?
        func flush() {
            if let number, let serial, !serial.isEmpty, let displayID {
                monitors.append(Monitor(number: number, name: name ?? "Monitor \(number)", serial: serial, displayID: displayID))
            }
        }
        for raw in output.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), let close = line.firstIndex(of: "]"), let n = Int(line[line.index(after: line.startIndex)..<close]) {
                flush()
                number = n
                name = nil
                serial = nil
                displayID = nil
            } else if let value = field(line, "- Product name:") {
                name = value
            } else if let value = field(line, "- AN Serial:") {
                serial = value
            } else if let value = field(line, "- Display ID:") {
                displayID = UInt32(value)
            }
        }
        flush()
        return monitors
    }

    private static func field(_ line: String, _ label: String) -> String? {
        line.hasPrefix(label) ? line.dropFirst(label.count).trimmingCharacters(in: .whitespaces) : nil
    }

    /// Display ID → "Left" / "Middle" / "Right" (side by side) or "Top" / "Bottom" (stacked); "" for a single one.
    public static func places(_ frames: [UInt32: CGRect]) -> [UInt32: String] {
        guard frames.count > 1 else { return frames.mapValues { _ in "" } }
        let xs = frames.values.map(\.midX), ys = frames.values.map(\.midY)
        let sideBySide = (xs.max()! - xs.min()!) >= (ys.max()! - ys.min()!)
        let ordered = frames.sorted { sideBySide ? $0.value.midX < $1.value.midX : $0.value.midY > $1.value.midY }
        let labels: [String]
        switch (sideBySide, ordered.count) {
        case (true, 2): labels = ["Left", "Right"]
        case (true, 3): labels = ["Left", "Middle", "Right"]
        case (false, 2): labels = ["Top", "Bottom"]
        case (false, 3): labels = ["Top", "Middle", "Bottom"]
        default: labels = ordered.indices.map { "\(sideBySide ? "From the left" : "From the top"), \($0 + 1)" }
        }
        return Dictionary(uniqueKeysWithValues: zip(ordered.map(\.key), labels))
    }

    /// The screens macOS shows now: display ID → frame.
    public static func screenFrames() -> [UInt32: CGRect] {
        var frames: [UInt32: CGRect] = [:]
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                frames[number.uint32Value] = screen.frame
            }
        }
        return frames
    }
}
