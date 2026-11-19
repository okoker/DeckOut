import AppKit
import DeckCore
import SwiftUI

/// The preset pull-down: the deck's presets with a check on the live one, then New Preset, Duplicate, Rename, then
/// Delete. New and Rename edit the name in place, with no dialog: Return applies, Esc cancels. Delete asks nothing;
/// ⌘Z brings it back. Picking a preset makes it live on the deck.
struct PresetMenu: View {
    @ObservedObject var model: AppModel
    var disabled = false
    @State private var renaming = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text("Preset").foregroundStyle(.secondary)
            if renaming {
                TextField("Name", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand { renaming = false }
                    .onChange(of: focused) { _, isFocused in if !isFocused { renaming = false } }
                    .onAppear { focused = true }
            } else {
                Menu {
                    ForEach(model.presetNames, id: \.self) { name in
                        Button { model.makeLive(name) } label: {
                            if name == model.livePreset { Label(name, systemImage: "checkmark") } else { Text(name) }
                        }
                    }
                    Divider()
                    Button("New Preset") { if let name = model.newPreset() { startRenaming(name) } }
                    Button("Duplicate") { model.duplicateLivePreset() }
                    Button("Rename") { startRenaming(model.livePreset) }
                    Divider()
                    Button("Delete") { model.deleteLivePreset() }
                        .disabled(model.presetNames.count <= 1)
                } label: {
                    Text(model.livePreset)
                }
                .fixedSize()
            }
        }
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    private func startRenaming(_ name: String) {
        draft = name
        renaming = true
    }

    private func commit() {
        if model.renameLivePreset(to: draft) {
            renaming = false
        } else {
            NSSound.beep()          // empty, or another preset already has that name
        }
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
        Button(model.store?.undoName.map { "Undo \($0)" } ?? "Undo") { perform(undo: true) }
            .keyboardShortcut("z", modifiers: .command)
        Button(model.store?.redoName.map { "Redo \($0)" } ?? "Redo") { perform(undo: false) }
            .keyboardShortcut("z", modifiers: [.command, .shift])
    }

    private func perform(undo: Bool) {
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, let manager = editor.undoManager,
           undo ? manager.canUndo : manager.canRedo {
            undo ? manager.undo() : manager.redo()
            return
        }
        undo ? model.store?.undo() : model.store?.redo()
    }
}
