import Foundation

private let logTimestamp: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
}()

/// Shadows Swift.print for the whole module, so every existing call site gains
/// a timestamp without being touched. Without one, the log records only the
/// order of events, which is not enough to tell a device that dropped twice in
/// a minute from one that dropped twice in a day.
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    let body = items.map { "\($0)" }.joined(separator: separator)
    Swift.print("[\(logTimestamp.string(from: Date()))] \(body)", terminator: terminator)
}
