import AppKit
import DeckCore
import SwiftUI

/// Lock photo mode's stage: the N4 showing the photo across its 14 screens exactly as they'll cut it. Drag to move,
/// pinch or scroll to zoom (mockup `docs/assets/config_app_lock_photo.html`).
struct PhotoStage: View {
    @ObservedObject var model: AppModel
    /// The drag's and pinch's last values: each event applies only its change since the last (no dead zone at the
    /// edge; a cancelled gesture resets them).
    @GestureState private var dragged: CGSize = .zero
    @GestureState private var pinched: CGFloat = 1

    private let face = DeckFace.of(.n4)

    var body: some View {
        let panel = model.lockPhotoImage.flatMap { LockPhoto.panel($0, framing: model.lockPhoto) }
        VStack(spacing: 14) {
            ZStack {
                DeckView(face: face, images: panel.map(Self.cut) ?? [:], captions: [:],
                         backdrop: model.showHiddenParts ? panel : nil, selection: .constant(nil))
                    .allowsHitTesting(false)
                if panel != nil {
                    Text("✥  Drag to move · scroll or pinch to zoom")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .foregroundStyle(.white)
                        .offset(y: face.size.height / 2 - 30)
                        .allowsHitTesting(false)
                } else {
                    Button("Choose a Photo…") { choose() }
                }
            }
            .frame(width: face.size.width, height: face.size.height)
            .contentShape(Rectangle())
            .gesture(drag.simultaneously(with: pinch))
            .overlay(ScrollZoom { delta in zoom(by: exp(delta * 0.01)) })
            Text("What the N4 shows while your Mac is locked")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StageBackground())
    }

    /// Each screen's piece of the panel, upright, by control id.
    static func cut(_ panel: CGImage) -> [String: CGImage] {
        var pieces: [String: CGImage] = [:]
        for (id, slot) in DeckModel.n4.keySlots.merging(DeckModel.n4.stripSlots, uniquingKeysWith: { a, _ in a }) {
            if let rect = LockPhoto.n4Rects[slot], let piece = panel.cropping(to: rect) { pieces[id] = piece }
        }
        return pieces
    }

    /// The face is drawn at half scale: a drag of 400 points is the whole face's width (offset 1.0).
    private var drag: some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($dragged) { value, last, _ in
                let delta = CGSize(width: value.translation.width - last.width,
                                   height: value.translation.height - last.height)
                last = value.translation
                DispatchQueue.main.async { model.moveLockPhoto(by: delta) }
            }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .updating($pinched) { value, last, _ in
                let factor = value.magnification / last
                last = value.magnification
                DispatchQueue.main.async { zoom(by: factor) }
            }
    }

    private func zoom(by factor: Double) {
        guard let current = model.lockPhoto else { return }
        model.setFraming(zoom: current.zoom * factor, name: "Zoom Lock Photo")
    }

    private func choose() {
        if let source = Chooser.image() { model.choosePhoto(source) }
    }
}

/// Scroll-wheel zoom over the stage (SwiftUI has no scroll-wheel gesture on macOS). Passes clicks and drags through.
struct ScrollZoom: NSViewRepresentable {
    let zoom: (Double) -> Void

    func makeNSView(context: Context) -> ScrollView { ScrollView(zoom: zoom) }
    func updateNSView(_ view: ScrollView, context: Context) { view.zoom = zoom }

    final class ScrollView: NSView {
        var zoom: (Double) -> Void
        init(zoom: @escaping (Double) -> Void) {
            self.zoom = zoom
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override func scrollWheel(with event: NSEvent) {
            guard event.momentumPhase.isEmpty else { return }       // no zooming on after the fingers lift
            zoom(Double(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 1 : 8))
        }
        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .scrollWheel ? self : nil
        }
    }
}
