import CoreGraphics
import Foundation

/// Whether the Mac's screen is locked.
///
/// The distributed notifications `com.apple.screenIsLocked` / `…Unlocked` give the instant response,
/// but they are not trusted alone: the "locked" one can fire when a screen saver merely starts, before
/// the password delay has passed, and no second one is known to follow when the Mac really locks. So
/// `recheck()` — called on every 5 s tick and before acting on a key, tap or swipe — reads the session's
/// own `CGSSessionScreenIsLocked` and corrects the state. Both mechanisms are undocumented by Apple but
/// used by Hammerspoon, Lunar and Stats. Main thread only.
final class LockMonitor: NSObject {
    private(set) var locked: Bool
    var onChange: ((Bool) -> Void)?
    private let isLockedNow: () -> Bool

    init(isLockedNow: @escaping () -> Bool = LockMonitor.sessionIsLocked) {
        self.isLockedNow = isLockedNow
        self.locked = isLockedNow()
        super.init()
    }

    /// The session's own lock flag. A missing key or no session dictionary means unlocked.
    static func sessionIsLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    func start() {
        // .deliverImmediately: the daemon is never the active app, and AppKit would otherwise hold these back.
        let center = DistributedNotificationCenter.default()
        center.addObserver(self, selector: #selector(screenLocked(_:)),
                           name: .init("com.apple.screenIsLocked"), object: nil, suspensionBehavior: .deliverImmediately)
        center.addObserver(self, selector: #selector(screenUnlocked(_:)),
                           name: .init("com.apple.screenIsUnlocked"), object: nil, suspensionBehavior: .deliverImmediately)
    }

    /// Re-read the session's lock flag and correct the state if it disagrees.
    func recheck() {
        set(isLockedNow())
    }

    /// What a lock / unlock notification does.
    func notificationArrived(locked: Bool) {
        set(locked)
    }

    @objc private func screenLocked(_ note: Notification) { notificationArrived(locked: true) }
    @objc private func screenUnlocked(_ note: Notification) { notificationArrived(locked: false) }

    private func set(_ newValue: Bool) {
        guard newValue != locked else { return }
        locked = newValue
        onChange?(newValue)
    }
}
