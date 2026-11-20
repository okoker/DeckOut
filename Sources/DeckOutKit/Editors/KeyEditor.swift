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
                IconRow(model: model, shape: .key(deck), choice: choice, icon: button?.icon, tile: button?.tile,
                        setIcon: { model.setIcon($0, button: control.id, on: deck) },
                        setTile: { model.setTile($0, button: control.id, on: deck) })
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

/// Shortcuts and media keys need the deck controller allowed under Accessibility. The app asks when such an action
/// is set up: Allow… has the controller ask macOS to list it, opens the pane, and checks again until it's allowed.
/// The controller never asks on its own: a prompt from a windowless process goes unseen.
struct AccessibilityBanner: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.link?.status?.accessibility == false {
            AccessibilityNote { model.requestAccessibility() }
        }
    }
}

struct AccessibilityNote: View {
    let allow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Keyboard shortcuts and media keys need DeckOut allowed under Accessibility.",
                  systemImage: "hand.raised.fill")
                .font(.system(size: 11.5))
                .fixedSize(horizontal: false, vertical: true)
            Text("Click Allow, then turn on DeckOutAgent in the list that opens.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Allow…", action: allow).controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(rgb: 0xFF9F0A).opacity(0.13)))
    }
}
