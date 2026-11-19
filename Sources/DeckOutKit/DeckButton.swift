import DeckCore
import SwiftUI

/// A small drawing of a deck, as in the mockup's deck buttons: in colour when the deck is plugged in, grey when not.
struct DeckGlyph: View {
    let deck: DeckKind
    var active: Bool
    var scale: CGFloat = 1

    var body: some View {
        Canvas { context, _ in
            context.scaleBy(x: scale * 1.2, y: scale * 1.2)
            let body = Path(roundedRect: CGRect(x: 0.5, y: 0.5, width: 29, height: 19), cornerRadius: 3.5)
            context.fill(body, with: .color(Color(rgb: 0x2A2A2C)))
            let key = active ? Color(rgb: 0x6AA8FF) : Color(rgb: 0x8E8E93)
            let knob = Color(rgb: 0x77777C)
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color, _ r: CGFloat = 0.5) {
                context.fill(Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r), with: .color(color))
            }
            func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ color: Color) {
                context.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)), with: .color(color))
            }
            switch deck {
            case .n4:
                for (i, x) in [4.0, 8.5, 13.5, 18.5, 23.0].enumerated() {
                    _ = i
                    rect(x, 3, 3, 3, key)
                    rect(x, 7.5, 3, 3, key)
                }
                rect(4, 12, 22, 2.2, Color(rgb: 0x4A4A4E), 0.6)
                for cx in [6.5, 12.0, 18.0, 23.5] { circle(cx, 16.8, 1.4, knob) }
            case .n3:
                for x in [4.0, 8.6, 13.2] {
                    rect(x, 3.5, 3.4, 3.4, key)
                    rect(x, 8.4, 3.4, 3.4, key)
                }
                circle(23, 7.5, 4, Color(rgb: 0x4A4A4E))
                for cx in [5.7, 10.3, 14.9] { circle(cx, 15.6, 1.4, knob) }
                for cx in [20.5, 25.3] { circle(cx, 15.6, 1.7, knob) }
            }
        }
        .frame(width: 36 * scale, height: 24 * scale)
        .opacity(active ? 1 : 0.45)
        .saturation(active ? 1 : 0)
    }
}

/// A deck button in the toolbar: the deck's glyph and name. Pressed in while its deck is on screen, greyed out
/// while it isn't plugged in.
struct DeckButton: View {
    let deck: DeckKind
    let plugged: Bool
    let shown: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                DeckGlyph(deck: deck, active: plugged)
                Text(deck.displayName).fontWeight(shown ? .semibold : .medium)
            }
            .padding(.leading, 5)
            .padding(.trailing, 10)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(shown ? Color.primary.opacity(0.13) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(plugged ? Color.primary : Color.secondary)
        .disabled(!plugged)
        .help(plugged ? "Set up the \(deck.displayName)" : "\(deck.displayName) isn't plugged in")
        .accessibilityAddTraits(shown ? .isSelected : [])
    }
}

extension DeckKind {
    var displayName: String { self == .n4 ? "N4" : "N3" }
    var fullName: String { self == .n4 ? "MiraBox N4" : "TreasLin N3" }
}
