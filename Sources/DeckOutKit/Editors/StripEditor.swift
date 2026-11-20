import DeckCore
import SwiftUI

/// A strip block, laid out like a key: what a tap does, then what the block shows (an icon like a key's, a live
/// reading, or nothing) and its settings. The two are independent: setting a tap never changes what it shows.
struct StripEditor: View {
    @ObservedObject var model: AppModel
    let control: FaceControl

    var body: some View {
        let block = model.stripBlock(control.id)
        let type = block?.type ?? .empty
        let tap = ActionChoice(action: block?.action ?? "none", step: block?.step)
        VStack(alignment: .leading, spacing: 12) {
            FieldRow("Tap") {
                ActionPicker(slot: .stripTap, choice: tap) { model.setStripTap($0, block: control.id) }
            }
            ActionFields(model: model, slot: .stripTap, choice: tap) { model.setStripTap($0, block: control.id) }
            ProblemNote(model: model, id: control.id, choice: tap)
            if tap.needsAccessibility { AccessibilityBanner(model: model) }
            Divider().padding(.vertical, 2)
            FieldRow("Shows") {
                Picker("", selection: Binding(get: { type }, set: { model.setStripType($0, block: control.id) })) {
                    Text("An icon").tag(StripBlockType.picture)
                    Divider()
                    Text("Internet latency").tag(StripBlockType.internet)
                    Text("CPU and memory").tag(StripBlockType.load)
                    Text("Volume").tag(StripBlockType.volume)
                    Divider()
                    Text("Nothing").tag(StripBlockType.empty)
                }
                .labelsHidden()
            }
            switch type {
            case .internet: internetFields(block ?? StripBlockConfig(type: .internet))
            case .picture:
                IconRow(model: model, shape: .stripBlock, choice: tap, icon: block?.icon, tile: block?.tile,
                        setIcon: { model.setStripIcon($0, block: control.id) },
                        setTile: { model.setStripTile($0, block: control.id) })
            case .load: FieldNote(text: "CPU use and memory, every few seconds; red when the Mac is short of memory.")
            case .volume: FieldNote(text: "The Mac's volume, as it changes.")
            case .empty: EmptyView()
            }
            Divider().padding(.vertical, 2)
            TestRow(choice: tap) { await model.test(tap) }
            Spacer(minLength: 0)
            Button("Clear Block") { model.clearStripBlock(control.id) }
                .buttonStyle(.plain)
                .foregroundStyle(Color(rgb: 0xFF3B30))
                .disabled(block == nil)
        }
    }

    @ViewBuilder
    private func internetFields(_ block: StripBlockConfig) -> some View {
        FieldRow("Host") {
            CommitTextField(value: block.host, placeholder: "one.one.one.one") { host in
                model.editStripBlock(control.id) { $0.host = host.trimmingCharacters(in: .whitespaces) }
            }
        }
        FieldRow("Arrow at") {
            Stepper(value: Binding(get: { Int(block.arrowMs) },
                                   set: { ms in model.editStripBlock(control.id) { $0.arrowMs = Double(ms) } }),
                    in: 0...50) {
                Text("\(Int(block.arrowMs)) ms change").monospacedDigit()
            }
            .fixedSize()
        }
        FieldRow("Red after") {
            Stepper(value: Binding(get: { Int(block.timeoutS.rounded()) },
                                   set: { s in model.editStripBlock(control.id) { $0.timeoutS = Double(s) } }),
                    in: 1...10) {
                Text("\(Int(block.timeoutS.rounded())) s without an answer").monospacedDigit()
            }
            .fixedSize()
        }
    }
}

/// What's wrong with a control's files, and the fix when there is one (make a script executable).
struct ProblemNote: View {
    @ObservedObject var model: AppModel
    let id: String
    let choice: ActionChoice

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let problem = model.problems[id] {
                HStack(spacing: 8) {
                    FieldNote(text: problem, warning: true)
                    if case .runScript(let path) = choice, MissingFiles.scriptProblem(path) == .notExecutable {
                        Button("Make Executable") { model.makeExecutable(path) }.controlSize(.small)
                    }
                }
            }
            if let path = filePath,
               let note = MissingFiles.guardedFolderNote(path, home: FileManager.default.homeDirectoryForCurrentUser.path) {
                FieldNote(text: note)
            }
        }
    }

    private var filePath: String? {
        switch choice {
        case .runScript(let path), .openFile(let path): return path.isEmpty ? nil : path
        default: return nil
        }
    }
}
