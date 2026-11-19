import DeckCore
import SwiftUI

/// A key (N4 key, N3 screen key) or an N3 button: its action, icon (screens only), Test and Clear.
struct KeyEditor: View {
    @ObservedObject var model: AppModel
    let deck: DeckKind
    let control: FaceControl

    var body: some View {
        let choice = model.choice(button: control.id, on: deck)
        let button = model.config?.button(deck, control.id)
        VStack(alignment: .leading, spacing: 12) {
            FieldRow("Action") {
                ActionPicker(slot: .key, choice: choice) { model.setAction($0, button: control.id, on: deck) }
            }
            ActionFields(model: model, slot: .key, choice: choice) { model.setAction($0, button: control.id, on: deck) }
            ProblemNote(model: model, id: control.id, choice: choice)
            if control.kind == .key {
                IconRow(model: model, deck: deck, id: control.id, choice: choice, icon: button?.icon)
            }
            if choice.needsAccessibility { AccessibilityBanner(model: model) }
            Divider().padding(.vertical, 2)
            TestRow(choice: choice) { await model.test(choice) }
            Spacer(minLength: 0)
            Button(control.kind == .key ? "Clear Key" : "Clear Button") { model.clearButton(control.id, on: deck) }
                .buttonStyle(.plain)
                .foregroundStyle(Color(rgb: 0xFF3B30))
                .disabled(button == nil)
        }
    }
}

/// Shortcuts and media keys need the deck controller allowed under Accessibility (Task 8 fills this in).
struct AccessibilityBanner: View {
    @ObservedObject var model: AppModel

    var body: some View {
        EmptyView()
    }
}
