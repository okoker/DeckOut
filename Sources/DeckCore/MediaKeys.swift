import AppKit

/// The Mac's media keys, sent as the keyboard sends them, so they control whatever is playing.
enum MediaKey: String, Equatable {
    case playPause = "media_play_pause"
    case next = "media_next"
    case previous = "media_previous"

    /// `NX_KEYTYPE_*`: 16 play, 19 fast (next), 20 rewind (previous): the codes an Apple keyboard's F8 / F9 / F7
    /// send. To be confirmed on the device (17 / 18 are NEXT / PREVIOUS).
    var code: Int {
        switch self {
        case .playPause: return 16
        case .next: return 19
        case .previous: return 20
        }
    }
}

enum MediaKeys {
    /// Posts the key down then up as system-defined events (subtype 8). Needs Accessibility, like `key:`;
    /// without it macOS drops the events silently. Call on the main thread.
    static func post(_ key: MediaKey) {
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                data1: (key.code << 16) | (state << 8), data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
