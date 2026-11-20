import AppKit
import DeckCore
import SwiftUI

/// Which preset sheet is open: New Preset, or Rename for the preset named when it opened.
enum PresetSheet: Identifiable {
    case new
    case rename(String)

    var id: String {
        switch self {
        case .new: return "new"
        case .rename(let name): return "rename:" + name
        }
    }
}

/// The preset pull-down (owner, 20/11/2026): the live preset (✓), then Default when another is live; New Preset…,
/// Rename…, Duplicate, Delete; a line; the other presets. It never leaves the toolbar: names are typed in a sheet
/// with Cancel. Delete asks nothing; ⌘Z brings it back. Picking a preset makes it live on the deck.
struct PresetMenu: View {
    @ObservedObject var model: AppModel
    @Binding var sheet: PresetSheet?
    var disabled = false

    var body: some View {
        let live = model.livePreset
        let layout = PresetMenuLayout.items(presets: model.presetNames, live: live)
        HStack(spacing: 6) {
            Text("Preset").foregroundStyle(.secondary)
            Menu {
                ForEach(layout.top, id: \.self) { presetItem($0, live: live) }
                Button("New Preset…") { sheet = .new }
                Button("Rename “\(live)”…") { sheet = .rename(live) }
                Button("Duplicate “\(live)”") { model.duplicateLivePreset() }
                Button("Delete “\(live)”") { model.deleteLivePreset() }
                    .disabled(model.presetNames.count <= 1)
                if !layout.rest.isEmpty {
                    Divider()
                    ForEach(layout.rest, id: \.self) { presetItem($0, live: live) }
                }
            } label: {
                Text(live)
            }
            .fixedSize()
        }
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    private func presetItem(_ name: String, live: String) -> some View {
        Button { model.makeLive(name) } label: {
            if name == live { Label(name, systemImage: "checkmark") } else { Text(name) }
        }
    }
}

/// The pull-down's order: the live preset first, then Default (the first preset in the file, whatever it's called)
/// when another is live; the rest, in file order, go below the actions.
enum PresetMenuLayout {
    static func items(presets: [String], live: String) -> (top: [String], rest: [String]) {
        guard let first = presets.first, first != live else { return ([live], presets.filter { $0 != live }) }
        let top = [live, first]
        return (top, presets.filter { !top.contains($0) })
    }
}

/// Names a new preset or renames one. Cancel (Esc) changes nothing; Create / Rename (Return) applies, greyed out
/// while the name is empty or taken, with the reason under the field.
struct PresetNameSheet: View {
    static let size = CGSize(width: 340, height: 150)
    let title: String
    let action: String
    let current: String?          // the preset being renamed: keeping its own name is fine
    let taken: [String]
    let commit: (String) -> Bool
    @State private var name: String
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    init(title: String, action: String, name: String, current: String?, taken: [String],
         commit: @escaping (String) -> Bool) {
        self.title = title
        self.action = action
        self.current = current
        self.taken = taken
        self.commit = commit
        _name = State(initialValue: name)
    }

    static func problem(_ name: String, taken: [String], current: String?) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Type a name." }
        if trimmed != current, taken.contains(trimmed) { return "There's already a preset called “\(trimmed)”." }
        return nil
    }

    var body: some View {
        let problem = Self.problem(name, taken: taken, current: current)
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
            Text(problem ?? " ")
                .font(.system(size: 11))
                .foregroundStyle(Color(rgb: 0xFF453A))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(action) {
                    if commit(name) { dismiss() } else { NSSound.beep() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(problem != nil)
            }
        }
        .padding(20)
        .frame(width: Self.size.width)
        .onAppear { focused = true }
    }
}

/// The deck's brightness, 0–100. A drag is one undo step.
struct BrightnessSlider: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "sun.max").foregroundStyle(.secondary)
            Slider(value: Binding(get: { Double(model.brightness) },
                                  set: { model.setBrightness(Int($0.rounded())) }), in: 0...100)
                .frame(width: 100)
                .help("Deck brightness")
            Text("\(model.brightness)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)
        }
    }
}

/// Edit → Undo / Redo: a text field being edited undoes its typing first; otherwise the last change to the decks.
struct UndoCommands: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Button(model.store?.undoName.map { "Undo \($0)" } ?? "Undo") {
            Self.perform(undo: true, in: NSApp.keyWindow, store: model.store)
        }
        .keyboardShortcut("z", modifiers: .command)
        .disabled(!Self.isEnabled(undo: true, model: model))
        Button(model.store?.redoName.map { "Redo \($0)" } ?? "Redo") {
            Self.perform(undo: false, in: NSApp.keyWindow, store: model.store)
        }
        .keyboardShortcut("z", modifiers: [.command, .shift])
        .disabled(!Self.isEnabled(undo: false, model: model))
    }

    /// Greyed out with nothing to undo (redo), but never while a field has been typed in: a greyed item swallows ⌘Z,
    /// and a text field has no ⌘Z of its own (macOS's key bindings have none), so its typing couldn't be undone.
    static func isEnabled(undo: Bool, model: AppModel) -> Bool {
        model.typingInAField || (undo ? model.store?.canUndo : model.store?.canRedo) == true
    }

    /// Typing in the focused field first. Deck changes only from the main window: in a sheet (Edit in Window…, a
    /// preset's name) ⌘Z stops at the field, so it never undoes a change behind the sheet, which could remove the
    /// command field and close its window, typing and all (BL-031).
    static func perform(undo: Bool, in window: NSWindow?, store: ConfigStore?) {
        if let editor = window?.firstResponder as? NSTextView, let manager = editor.undoManager,
           undo ? manager.canUndo : manager.canRedo {
            undo ? manager.undo() : manager.redo()
            return
        }
        guard window?.sheetParent == nil else { return }
        undo ? store?.undo() : store?.redo()
    }
}
