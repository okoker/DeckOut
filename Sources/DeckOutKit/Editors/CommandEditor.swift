import AppKit
import SwiftUI

/// Run Command's field: the label on its own line with Edit in Window… beside it, and the command at the panel's
/// full width below (3–10 lines, then it scrolls). Return applies, Option-Return starts a new line.
struct CommandField: View {
    let command: String
    let change: (String) -> Void
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Command").foregroundStyle(.secondary)
                Spacer()
                Button("Edit in Window…", action: openWindow).controlSize(.small)
            }
            .font(.system(size: 12.5))
            CommitTextField(value: command, placeholder: "open -a Notes", multiline: true, monospaced: true,
                            lines: 3...10, commit: change)
        }
        .sheet(isPresented: $editing) { CommandSheet(command: command, save: change) }
    }

    /// Ends typing in the field first, so what was typed there is applied and the window opens on it.
    private func openWindow() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        DispatchQueue.main.async { editing = true }
    }
}

/// The command in a window big enough to read it: Cancel (Esc) changes nothing, Save (⌘Return, the prominent button)
/// applies it.
struct CommandSheet: View {
    static let size = CGSize(width: 640, height: 380)
    let save: (String) -> Void
    @State private var draft: String
    @Environment(\.dismiss) private var dismiss

    init(command: String, save: @escaping (String) -> Void) {
        _draft = State(initialValue: command)
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Command").font(.headline)
            CodeTextView(text: $draft)
            HStack(spacing: 10) {
                Text("Runs in zsh with your shell's PATH. ⌘Return saves.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(18)
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

/// Plain text for commands: monospaced, wrapped, scrolling, and exactly what's typed. Smart quotes, dashes, text
/// replacements and spelling fixes are off whatever the person's macOS text settings: any of them breaks a command.
struct CodeTextView: NSViewRepresentable {
    @Binding var text: String

    static func makeTextView() -> NSTextView {
        let view = NSTextView()
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.smartInsertDeleteEnabled = false
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.textContainerInset = NSSize(width: 4, height: 6)
        return view
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let view = Self.makeTextView()
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.string = text
        view.delegate = context.coordinator
        scroll.documentView = view
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        view.string = text
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text.wrappedValue = view.string
        }
    }
}
