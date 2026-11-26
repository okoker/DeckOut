import DeckCore
import SwiftUI

/// A knob's list (N4): the items turning the knob steps through, and the selected one's action and icon. The row
/// being edited and the item the deck shows are separate (owner, 26/11/2026): the deck keeps its own pick, marked
/// "On the deck", until the knob is turned.
struct KnobListEditor: View {
    @ObservedObject var model: AppModel
    let items: [ButtonConfig]
    @Binding var selected: Int?
    /// The item the deck shows now, as the agent reports it.
    let deckPick: Int?
    let add: () -> Void
    let remove: (Int) -> Void
    let move: (_ from: Int, _ to: Int) -> Void
    let setAction: (Int, ActionChoice) -> Void
    let setIcon: (Int, String?) -> Void
    let setTile: (Int, IconTile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            rows
            buttons
            if let index = selected, items.indices.contains(index) {
                Divider().padding(.vertical, 2)
                itemEditor(index).id(Self.itemIdentity(index: index, count: items.count))
            } else if items.isEmpty {
                Text("Add a website or an app with +.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// What the selected item's editor is built for: fresh fields per item, and after every add or remove (a remove
    /// can leave the selection on the same number, and text half-typed for the removed item must not land on the
    /// one that moved up).
    static func itemIdentity(index: Int, count: Int) -> String { "\(index) of \(count)" }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                row(index, item)
                if index < items.count - 1 { Divider().padding(.leading, 60) }
            }
        }
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator))
    }

    private func row(_ index: Int, _ item: ButtonConfig) -> some View {
        HStack(spacing: 8) {
            thumbnail(item.icon)
            Text(ActionNames.itemName(item))
                .font(.system(size: 12.5))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if index == deckPick {
                Text("On the deck")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().strokeBorder(.secondary.opacity(0.6)))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(index == selected ? Color.accentColor.opacity(0.22) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { selected = index }
    }

    /// The item's icon as the block above the knob shows it (176 × 112, here at a quarter), black without one.
    private func thumbnail(_ icon: String?) -> some View {
        let size = CGSize(width: 44, height: 28)
        return Group {
            if let icon, let image = IconShape.stripBlock.preview(icon) {
                Image(decorative: image, scale: 1).resizable().interpolation(.high)
            } else {
                Color.black
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private var buttons: some View {
        HStack(spacing: 6) {
            Button { add() } label: { Image(systemName: "plus") }
            Button { if let selected { remove(selected) } } label: { Image(systemName: "minus") }
                .disabled(selected == nil || items.isEmpty)
            Spacer()
            Button { step(-1) } label: { Image(systemName: "chevron.up") }
                .disabled((selected ?? 0) <= 0)
            Button { step(1) } label: { Image(systemName: "chevron.down") }
                .disabled(selected.map { $0 >= items.count - 1 } ?? true)
        }
        .controlSize(.small)
    }

    private func step(_ by: Int) {
        guard let from = selected else { return }
        move(from, from + by)
        selected = from + by
    }

    @ViewBuilder
    private func itemEditor(_ index: Int) -> some View {
        let item = items[index]
        let choice = ActionChoice(action: item.action, step: item.step)
        FieldRow("Item \(index + 1)") {
            ActionPicker(slot: .key, choice: choice) { setAction(index, $0) }
        }
        ActionFields(model: model, slot: .key, choice: choice) { setAction(index, $0) }
        IconRow(model: model, shape: .stripBlock, choice: choice, icon: item.icon, tile: item.tile,
                setIcon: { setIcon(index, $0) }, setTile: { setTile(index, $0) })
        if choice.needsAccessibility { AccessibilityBanner(model: model) }
        TestRow(choice: choice) { await model.test(choice) }
    }
}
