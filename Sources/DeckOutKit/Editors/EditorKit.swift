import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One labelled row of the editor, the label right-aligned in its own column (mockup).
struct FieldRow<Content: View>: View {
    let label: String
    static var labelWidth: CGFloat { 66 }
    @ViewBuilder let content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: FieldRow.labelWidth, alignment: .trailing)
                .lineLimit(1)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12.5))
    }
}

/// Small grey text under a row, lined up with the fields.
struct FieldNote: View {
    let text: String
    var warning = false

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(warning ? Color(rgb: 0xFF453A) : .secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, FieldRow<EmptyView>.labelWidth + 10)
    }
}

/// A text field that applies when you finish: Return, or leaving the field. While you type nothing is saved.
struct CommitTextField: View {
    let value: String
    let placeholder: String
    var multiline = false
    var monospaced = false
    let commit: (String) -> Void
    @State private var draft = ""
    /// The value the draft started from. Until the person types, the field follows the value (an undo shows at
    /// once), and leaving it commits nothing.
    @State private var base = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if multiline {
                TextField(placeholder, text: $draft, axis: .vertical).lineLimit(2...6)
            } else {
                TextField(placeholder, text: $draft)
            }
        }
        .textFieldStyle(.roundedBorder)
        .font(monospaced ? .system(size: 11.5, design: .monospaced) : .system(size: 12.5))
        .focused($focused)
        .onSubmit(apply)
        .onChange(of: focused) { _, isFocused in if !isFocused { apply() } }
        .onAppear {
            draft = value
            base = value
        }
        .onChange(of: value) { _, newValue in
            if draft == base { draft = newValue }      // not typed in: follow
            base = newValue
        }
    }

    private func apply() {
        guard draft != base else { return }
        commit(draft)
    }
}

/// Picking files with the standard open panel.
enum Chooser {
    static func app() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    static func fileOrFolder() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    static func script() -> String? {
        let panel = NSOpenPanel()
        panel.prompt = "Choose"
        panel.message = "Pick the script to run. It runs where it is: moving or renaming it later breaks the key."
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    static func image() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

/// The editor's section title (mockup: small caps, grey).
struct EditorTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(.secondary)
            .padding(.bottom, 2)
    }
}
