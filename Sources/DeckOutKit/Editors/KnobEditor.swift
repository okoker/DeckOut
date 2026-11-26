import DeckCore
import SwiftUI

/// A knob: what turning it does (volume or monitor brightness, so much per click) and what pressing it does; or, on
/// the N4, a list it picks from, shown on the strip block above it (docs/design/knob_lists.md).
struct KnobEditor: View {
    @ObservedObject var model: AppModel
    let deck: DeckKind
    let control: FaceControl
    /// The list item being edited (not the one the deck shows).
    @State private var selectedItem: Int?

    var body: some View {
        let (turn, press) = model.knobChoices(control.id, on: deck)
        let list = model.config?.knob(deck, control.id)?.list
        VStack(alignment: .leading, spacing: 12) {
            FieldRow("Turn") {
                ActionPicker(slot: .knobTurn, choice: turn,
                             extra: deck == .n4 ? ("Pick from a list", list != nil, { model.makeKnobList(control.id) }) : nil) {
                    model.setKnob(control.id, on: deck, turn: $0)
                }
            }
            if let list {
                FieldNote(text: "Press the knob, or tap the block above, to open the pick.")
                ProblemNote(model: model, id: control.id, choice: .nothing)
                listEditor(list)
            } else {
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
            }
            Spacer(minLength: 0)
            Button("Clear Knob") { model.clearKnob(control.id, on: deck) }
                .buttonStyle(.plain)
                .foregroundStyle(Color(rgb: 0xFF3B30))
                .disabled(model.config?.knob(deck, control.id) == nil)
        }
    }

    private func listEditor(_ list: [ButtonConfig]) -> some View {
        let knob = control.id
        return KnobListEditor(
            model: model, items: list, selected: $selectedItem, deckPick: model.livePicks[knob] ?? (list.isEmpty ? nil : 0),
            add: { selectedItem = model.addListItem(knob: knob, after: selectedItem) },
            remove: { at in
                model.removeListItem(knob: knob, at: at)
                selectedItem = list.count > 1 ? min(at, list.count - 2) : nil
            },
            move: { model.moveListItem(knob: knob, from: $0, to: $1) },
            setAction: { model.setListItemAction($1, knob: knob, at: $0) },
            setIcon: { model.setListItemIcon($1, knob: knob, at: $0) },
            setTile: { model.setListItemTile($1, knob: knob, at: $0) })
    }
}
