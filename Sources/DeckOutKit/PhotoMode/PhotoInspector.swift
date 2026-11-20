import AppKit
import DeckCore
import SwiftUI

/// Lock photo mode's panel (mockup): the photo, zoom, position, the two switches, Remove Photo and Done.
struct PhotoInspector: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let framing = model.lockPhoto
        VStack(alignment: .leading, spacing: 12) {
            EditorTitle(text: "Lock photo · N4")
            FieldRow("Photo") {
                HStack(spacing: 8) {
                    if let image = model.lockPhotoImage {
                        Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 52, height: 30).clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        Text("None chosen").foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button("Choose…") { if let source = Chooser.image() { model.choosePhoto(source) } }
                }
            }
            if let problem = model.photoProblem { FieldNote(text: problem, warning: true) }
            if let framing {
                FieldRow("Zoom") {
                    HStack(spacing: 6) {
                        Text("−").foregroundStyle(.secondary)
                        Slider(value: Binding(get: { framing.zoom },
                                              set: { model.setFraming(zoom: $0, name: "Zoom Lock Photo") }), in: 1...4)
                        Text("+").foregroundStyle(.secondary)
                        Text("\(Int((framing.zoom * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                }
                FieldRow("Position") {
                    HStack {
                        Text("Drag on the deck")
                        Spacer()
                        Button("Reset") { model.resetFraming() }
                    }
                }
            }
            Divider().padding(.vertical, 2)
            switchRow("Show on the deck", isOn: $model.showOnDeck,
                      note: "The real N4 shows the photo while you edit. It goes back to your keys when you click Done.")
            switchRow("Show hidden parts", isOn: $model.showHiddenParts,
                      note: "Faintly shows what falls behind the frames.")
            Divider().padding(.vertical, 2)
            FieldNote(text: "The app keeps its own copy of the photo, so moving or deleting the original changes nothing.")
            Spacer(minLength: 0)
            HStack {
                Button("Remove Photo") { model.removePhoto() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(rgb: 0xFF3B30))
                    .disabled(framing == nil)
                Spacer()
                Button("Done") { model.leavePhotoMode() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background.secondary)
    }

    private func switchRow(_ title: String, isOn: Binding<Bool>, note: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: isOn).toggleStyle(.switch).controlSize(.mini).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5))
                Text(note).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, FieldRow<EmptyView>.labelWidth + 10 - 40)
    }
}
