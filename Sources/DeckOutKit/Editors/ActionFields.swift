import AppKit
import DeckCore
import SwiftUI

/// The Action pop-up: the menu for this kind of control, grouped. A control set by hand to something off the menu
/// (ZR7, an unknown string) shows it at the top, and picking anything else replaces it.
struct ActionPicker: View {
    let slot: ControlSlot
    let choice: ActionChoice
    let pick: (ActionChoice) -> Void

    var body: some View {
        let current = choice.kind(in: slot)
        let groups = ActionChoice.menu(for: slot)
        let onMenu = groups.joined().contains(current)
        Picker("", selection: Binding(get: { current }, set: { kind in
            if kind != current { pick(ActionChoice.make(kind)) }
        })) {
            if !onMenu {
                Text("\(current.title) (set by hand)").tag(current)
                Divider()
            }
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                if index > 0 { Divider() }
                ForEach(group, id: \.self) { kind in Text(kind.title).tag(kind) }
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity)
    }
}

extension ActionChoice.Kind: Hashable {}

/// The fields for the chosen action. Each applies when it's finished (Return, leaving the field, a file chosen).
struct ActionFields: View {
    @ObservedObject var model: AppModel
    let slot: ControlSlot
    let choice: ActionChoice
    let change: (ActionChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            fields
            if let note { FieldNote(text: note.text, warning: note.warning) }
        }
    }

    @ViewBuilder
    private var fields: some View {
        switch choice {
        case .openApp(let path):
            FieldRow("App") {
                HStack(spacing: 7) {
                    if !path.isEmpty {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 18, height: 18)
                        Text(ActionNames.appName(path)).lineLimit(1)
                    } else {
                        Text("No app chosen").foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button("Choose…") { if let app = Chooser.app() { change(.openApp(app)) } }
                }
            }
        case .openWebsite(let url):
            FieldRow("Website") {
                CommitTextField(value: url, placeholder: "https://example.com") { change(.openWebsite($0)) }
            }
        case .openFile(let path):
            FieldRow("Open") {
                fileLine(path, empty: "Nothing chosen") { if let file = Chooser.fileOrFolder() { change(.openFile(file)) } }
            }
        case .keyboardShortcut(let keys):
            FieldRow("Shortcut") {
                ShortcutRecorder(shortcut: keys) { change(.keyboardShortcut($0)) }
            }
        case .runShortcut(let name):
            FieldRow("Shortcut") { ShortcutPicker(model: model, name: name) { change(.runShortcut($0)) } }
        case .volume(let step):
            stepRow(step, unit: "%") { change(.volume(step: $0)) }
        case .monitorBrightness(let step):
            stepRow(step, unit: "%") { change(.monitorBrightness(step: $0)) }
        case .runScript(let path):
            FieldRow("Script") {
                fileLine(path, empty: "No script chosen") { if let script = Chooser.script() { change(.runScript(script)) } }
            }
        case .runCommand(let command):
            CommandField(model: model, command: command) { change(.runCommand($0)) }
        case .zr7Volume, .zr7Mute, .unknown:
            FieldRow("Set to") {
                Text(choice.action).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        case .nothing, .playPause, .nextTrack, .previousTrack, .mute, .switchMonitor:
            EmptyView()
        }
    }

    private func fileLine(_ path: String, empty: String, choose: @escaping () -> Void) -> some View {
        HStack(spacing: 7) {
            if path.isEmpty {
                Text(empty).foregroundStyle(.secondary)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 16, height: 16)
                Text((path as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle).help(path)
            }
            Spacer(minLength: 4)
            Button("Choose…", action: choose)
        }
    }

    /// Volume and brightness: on a key, up or down by the step (the sign is the menu item); on a knob turn, per click.
    private func stepRow(_ step: Int, unit: String, set: @escaping (Int) -> Void) -> some View {
        let sign = step < 0 ? -1 : 1
        return FieldRow(slot == .knobTurn ? "Per click" : "Step") {
            Stepper(value: Binding(get: { max(1, abs(step)) }, set: { set(sign * $0) }), in: 1...20) {
                Text("\(max(1, abs(step)))\(unit)").monospacedDigit()
            }
            .fixedSize()
        }
    }

    /// What's missing or wrong, in the agent's own words once a value is there.
    private var note: (text: String, warning: Bool)? {
        switch choice {
        case .openApp(let p) where p.isEmpty: return ("Choose the app to open. Its icon goes on the key.", false)
        case .openApp: return ("Its icon goes on the key, unless you choose an image.", false)
        case .openFile(let p) where p.isEmpty: return ("Choose a file or folder to open.", false)
        case .runScript(let p) where p.isEmpty: return ("Scripts run where they are: moving or renaming one breaks the key.", false)
        case .runScript: return ("Runs where it is: moving or renaming it breaks the key.", false)
        case .keyboardShortcut(let k) where k.isEmpty: return ("Click, then press the keys.", false)
        case .runShortcut(let n) where n.isEmpty: return ("Pick one of your Shortcuts.", false)
        case .runCommand(let c) where c.isEmpty: return ("A command for zsh, with your shell's PATH. For advanced use.", false)
        case .zr7Volume, .zr7Mute: return ("ZR7 actions are set by hand. Pick another action to replace it.", false)
        case .unknown: return ("Not an action DeckOut knows. Pick another action to replace it.", true)
        default: break
        }
        if let problem = ActionCheck.problem(choice.action) { return (Self.plain(problem), true) }
        return nil
    }

    /// The agent's message without its config prefix: "url: needs …" → "Needs …".
    static func plain(_ problem: String) -> String {
        var text = problem
        if let colon = text.firstIndex(of: ":"), text[..<colon].allSatisfy({ $0.isLetter }), text[text.index(after: colon)...].hasPrefix(" ") {
            text = String(text[text.index(colon, offsetBy: 2)...])
        }
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

/// Apple Shortcuts by name, from `shortcuts list`; a text field if there are none to list.
struct ShortcutPicker: View {
    @ObservedObject var model: AppModel
    let name: String
    let pick: (String) -> Void

    var body: some View {
        Group {
            if let names = model.shortcutNames, !names.isEmpty {
                Picker("", selection: Binding(get: { name }, set: pick)) {
                    if name.isEmpty { Text("Choose…").tag("") }
                    if !name.isEmpty && !names.contains(name) { Text("\(name) (not found)").tag(name) }
                    ForEach(names, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            } else {
                CommitTextField(value: name, placeholder: "Shortcut name", commit: pick)
            }
        }
        .onAppear { model.loadShortcutNames() }
    }
}
