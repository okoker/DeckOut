import AppKit
import DeckCore
import SwiftUI

/// Records a keyboard shortcut by pressing it: click, then press the keys. Esc on its own cancels. Only keys the
/// agent can post are taken (`KeyNames`); anything else says so instead of saving a shortcut that does nothing.
struct ShortcutRecorder: View {
    let shortcut: String
    let onRecord: (String) -> Void
    @State private var recording = false
    @State private var message: String?
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { recording ? stop() : start() }) {
                Text(label)
                    .font(.system(size: 12.5, weight: shortcut.isEmpty || recording ? .regular : .medium))
                    .foregroundStyle(recording ? Color.accentColor : shortcut.isEmpty ? .secondary : .primary)
                    .frame(minWidth: 150)
            }
            if let message {
                Text(message).font(.system(size: 11)).foregroundStyle(.red)
            }
        }
        .onDisappear(perform: stop)
    }

    private var label: String {
        if recording { return "Press the shortcut…" }
        return shortcut.isEmpty ? "Click to record" : ActionNames.shortcutSymbols(shortcut)
    }

    private func start() {
        message = nil
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 0x35, flags.subtracting([.function, .numericPad]).isEmpty {
                stop()                                   // Esc on its own: cancel
                return nil
            }
            if let recorded = KeyNames.shortcut(keyCode: event.keyCode, command: flags.contains(.command),
                                                shift: flags.contains(.shift), option: flags.contains(.option),
                                                control: flags.contains(.control)) {
                onRecord(recorded)
                stop()
            } else {
                message = "That key can't be sent; try another."
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}
