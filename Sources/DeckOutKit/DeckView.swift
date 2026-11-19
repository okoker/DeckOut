import DeckCore
import SwiftUI

/// A deck drawn as it looks: its body, black screens showing what the deck shows, the strip as one panel, knobs and
/// buttons, and a red ring around the selected control. Clicking a control selects it. Sizes in points from
/// `DeckFace`; colours from the approved mockup (`docs/assets/config_app_main_window.html`).
public struct DeckView: View {
    let face: DeckFace
    let images: [String: CGImage]
    let captions: [String: String]
    @Binding var selection: String?

    public static let ringWidth: CGFloat = 3
    public static let ringGap: CGFloat = 5
    static let red = Color(rgb: 0xFF3B30)

    public init(face: DeckFace, images: [String: CGImage], captions: [String: String], selection: Binding<String?>) {
        self.face = face
        self.images = images
        self.captions = captions
        _selection = selection
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(stops: [.init(color: Color(rgb: 0x303033), location: 0),
                                             .init(color: Color(rgb: 0x1B1B1D), location: 0.55),
                                             .init(color: Color(rgb: 0x141416), location: 1)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                .shadow(color: .black.opacity(0.30), radius: 20, y: 11)
            if let strip = stripFrame {
                stripPanel(strip)
            }
            ForEach(face.controls) { control in
                place(control) { controlView(control) }
            }
            ForEach(face.controls.filter { $0.kind == .knob }) { knob in
                Text(captions[knob.id] ?? "—")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color(rgb: 0x8E8E93))
                    .lineLimit(1)
                    .frame(width: 96)
                    .position(x: knob.frame.midX, y: knob.frame.maxY + 12)
            }
            if let id = selection, let selected = face.control(id) {
                ring(selected).allowsHitTesting(false)
            }
        }
        .frame(width: face.size.width, height: face.size.height, alignment: .topLeading)
    }

    // MARK: - Controls

    private func place<Content: View>(_ control: FaceControl, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: control.frame.width, height: control.frame.height)
            .contentShape(Rectangle())
            .onTapGesture { selection = control.id }
            .position(x: control.frame.midX, y: control.frame.midY)
            .accessibilityLabel(control.label)
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func controlView(_ control: FaceControl) -> some View {
        switch control.kind {
        case .key:
            screen(images[control.id], cornerRadius: 7)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(rgb: 0x0A0A0B), lineWidth: 2).padding(-1))
                .overlay(RoundedRectangle(cornerRadius: 9.5).stroke(Color(rgb: 0x3B3B3E), lineWidth: 1.5).padding(-2.75))
                .shadow(color: .black.opacity(0.6), radius: 3, y: 3)
        case .stripBlock:
            // Drawn inside the strip panel; only its image here.
            if let image = images[control.id] {
                Image(decorative: image, scale: 1).resizable().interpolation(.high)
            } else {
                Color.clear
            }
        case .knob:
            Circle()
                .fill(RadialGradient(colors: [Color(rgb: 0x5D5D61), Color(rgb: 0x2A2A2D), Color(rgb: 0x111113)],
                                     center: UnitPoint(x: 0.36, y: 0.30), startRadius: 0,
                                     endRadius: control.frame.width * 0.75))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                .shadow(color: .black.opacity(0.55), radius: 4.5, y: 5)
        case .button:
            Circle()
                .fill(RadialGradient(colors: [Color(rgb: 0x2C2C2E), Color(rgb: 0x111113)],
                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: control.frame.width * 0.7))
                .overlay(Circle().strokeBorder(Color(rgb: 0x3B3B3E), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.5), radius: 3, y: 3)
        }
    }

    private func screen(_ image: CGImage?, cornerRadius: CGFloat) -> some View {
        ZStack {
            Color.black
            if let image {
                Image(decorative: image, scale: 1).resizable().interpolation(.high)
            } else {
                Text("+").font(.system(size: 20, weight: .light)).foregroundStyle(Color(rgb: 0x3A3A3C))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    // MARK: - Strip

    private var stripFrame: CGRect? {
        let blocks = face.controls.filter { $0.kind == .stripBlock }.map(\.frame)
        guard let first = blocks.first else { return nil }
        return blocks.dropFirst().reduce(first) { $0.union($1) }
    }

    /// One black panel with thin lines between its four areas (owner's pick, option 1).
    private func stripPanel(_ frame: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black)
            ForEach(face.controls.filter { $0.kind == .stripBlock }.dropFirst()) { block in
                Rectangle().fill(Color(rgb: 0x2C2C2F))
                    .frame(width: 1, height: frame.height)
                    .position(x: block.frame.minX - frame.minX - (block.frame.minX - previousMaxX(block)) / 2,
                              y: frame.height / 2)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(rgb: 0x0A0A0B), lineWidth: 2).padding(-1))
        .overlay(RoundedRectangle(cornerRadius: 11.5).stroke(Color(rgb: 0x3B3B3E), lineWidth: 1.5).padding(-2.75))
        .shadow(color: .black.opacity(0.6), radius: 3, y: 3)
        .position(x: frame.midX, y: frame.midY)
        .allowsHitTesting(false)
    }

    private func previousMaxX(_ block: FaceControl) -> CGFloat {
        face.controls.filter { $0.kind == .stripBlock && $0.frame.maxX <= block.frame.minX }.map(\.frame.maxX).max()
            ?? block.frame.minX
    }

    // MARK: - Selection

    @ViewBuilder
    private func ring(_ control: FaceControl) -> some View {
        let w = Self.ringWidth, gap = Self.ringGap
        switch control.kind {
        case .key:
            RoundedRectangle(cornerRadius: 7 + gap + w / 2, style: .continuous)
                .stroke(Self.red, lineWidth: w)
                .frame(width: control.frame.width + 2 * gap + w, height: control.frame.height + 2 * gap + w)
                .position(x: control.frame.midX, y: control.frame.midY)
        case .stripBlock:
            // Inside the panel: the blocks touch their neighbours.
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Self.red, lineWidth: 2.5)
                .frame(width: control.frame.width, height: control.frame.height)
                .position(x: control.frame.midX, y: control.frame.midY)
        case .knob, .button:
            Circle()
                .stroke(Self.red, lineWidth: w)
                .frame(width: control.frame.width + 2 * (gap - 1) + w, height: control.frame.height + 2 * (gap - 1) + w)
                .position(x: control.frame.midX, y: control.frame.midY)
        }
    }
}
