import DeckCore
import SwiftUI

/// A knob: what turning it does (volume or monitor brightness, so much per click) and what pressing it does.
struct KnobEditor: View {
    @ObservedObject var model: AppModel
    let deck: DeckKind
    let control: FaceControl

    var body: some View {
        let (turn, press) = model.knobChoices(control.id, on: deck)
        VStack(alignment: .leading, spacing: 12) {
            FieldRow("Turn") {
                ActionPicker(slot: .knobTurn, choice: turn) { model.setKnob(control.id, on: deck, turn: $0) }
            }
            ActionFields(model: model, slot: .knobTurn, choice: turn) { model.setKnob(control.id, on: deck, turn: $0) }
            Divider().padding(.vertical, 2)
            FieldRow("Press") {
                ActionPicker(slot: .knobPress, choice: press) { model.setKnob(control.id, on: deck, press: $0) }
            }
            ActionFields(model: model, slot: .knobPress, choice: press) { model.setKnob(control.id, on: deck, press: $0) }
            ProblemNote(model: model, id: control.id, choice: press)
            if press.needsAccessibility { AccessibilityBanner(model: model) }
            Divider().padding(.vertical, 2)
            TestRow(choice: press) { await model.test(press) }
            Spacer(minLength: 0)
            Button("Clear Knob") { model.clearKnob(control.id, on: deck) }
                .buttonStyle(.plain)
                .foregroundStyle(Color(rgb: 0xFF3B30))
                .disabled(model.config?.knob(deck, control.id) == nil)
        }
    }
}
