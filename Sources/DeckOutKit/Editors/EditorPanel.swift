import DeckCore
import SwiftUI

/// The right-hand panel: the editor for the selected control, or a hint.
struct EditorPanel: View {
    @ObservedObject var model: AppModel
    let face: DeckFace

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let id = model.selection, let control = face.control(id) {
                EditorTitle(text: control.label)
                switch control.kind {
                case .key, .button:
                    KeyEditor(model: model, deck: face.deck, control: control)
                case .knob:
                    KnobEditor(model: model, deck: face.deck, control: control)
                case .stripBlock:
                    StripEditor(model: model, control: control)
                }
            } else {
                Text("Nothing selected")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Click a key, strip block or knob on the deck to set it up.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background.secondary)
        .id(model.selection)   // a fresh editor (and Test result) per control
    }
}
