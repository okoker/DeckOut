import DeckCore
import SwiftUI

/// The right-hand panel: the editor for the selected control, or a hint.
struct EditorPanel: View {
    @ObservedObject var model: AppModel
    let face: DeckFace

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                content.frame(minHeight: proxy.size.height, alignment: .top)   // so Clear sits at the bottom
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background.secondary)
        .id(model.selection)   // a fresh editor (and Test result) per control
    }

    /// At least the panel's height, so the editor's Clear sits at the bottom; scrolls when it's taller than the window
    /// (a long command with a strip block's icon settings).
    private var content: some View {
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
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
