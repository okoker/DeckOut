import CoreGraphics
import Foundation
import ImageIO

public enum ControlKind: Hashable {
    case key, stripBlock, knob, button
}

/// One control as the app draws it: its config key, where it sits on the deck (points, top-left origin) and its
/// name for a person.
public struct FaceControl: Identifiable, Hashable {
    public let id: String
    public let kind: ControlKind
    public let frame: CGRect
    public let label: String
}

/// A deck's face as the config app draws it.
///
/// - N4: half the measured key-image pixels (`LockPhoto.n4Rects`: keys 56 pt at 86 pt pitch, rows 88 apart, the
///   strip's blocks 88 × 56 at 104 pitch, 176 below the top row); knobs drawn by eye under the strip (mockup
///   `docs/assets/config_app_main_window.html`).
/// - N3: by eye from `docs/assets/streamdeck.jpg`, straightened: 3 × 2 screens, the big knob right of them, three
///   buttons under the screens, two small knobs under the big knob. Nothing is cut to this drawing.
public struct DeckFace {
    public let deck: DeckKind
    public let size: CGSize
    public let controls: [FaceControl]

    public static let n4Padding = (top: CGFloat(26), left: CGFloat(28), right: CGFloat(28), bottom: CGFloat(16))

    public static func of(_ deck: DeckKind) -> DeckFace {
        deck == .n4 ? n4 : n3
    }

    public func control(_ id: String) -> FaceControl? { controls.first { $0.id == id } }

    // MARK: - N4

    private static let n4: DeckFace = {
        let p = n4Padding
        var controls: [FaceControl] = []
        func half(_ slot: UInt8) -> CGRect {
            let r = LockPhoto.n4Rects[slot]!
            return CGRect(x: p.left + r.minX / 2, y: p.top + r.minY / 2, width: r.width / 2, height: r.height / 2)
        }
        for number in 1...10 {
            let key = "key_\(number)"
            controls.append(FaceControl(id: key, kind: .key, frame: half(DeckModel.n4.keySlots[key]!),
                                        label: "Key \(number) · \(number <= 5 ? "top" : "bottom") row"))
        }
        for block in 1...4 {
            controls.append(FaceControl(id: "\(block)", kind: .stripBlock, frame: half(DeckModel.n4.stripSlots["\(block)"]!),
                                        label: "Strip block \(block)"))
        }
        // Knobs: 44 pt, centred in four 100 pt columns as wide as the strip, 20 pt below it.
        let knobTop = p.top + 176 + 56 + 20
        for knob in 1...4 {
            let centreX = p.left + CGFloat(knob - 1) * 100 + 50
            controls.append(FaceControl(id: "knob_\(knob)", kind: .knob,
                                        frame: CGRect(x: centreX - 22, y: knobTop, width: 44, height: 44),
                                        label: "Knob \(knob)"))
        }
        // Room under the knobs for their captions.
        let height = knobTop + 44 + knobCaptionHeight + p.bottom
        return DeckFace(deck: .n4, size: CGSize(width: p.left + 400 + p.right, height: height), controls: controls)
    }()

    /// Space the app leaves under each knob for its caption.
    public static let knobCaptionHeight: CGFloat = 19

    // MARK: - N3

    private static let n3: DeckFace = {
        let p: CGFloat = 28, key: CGFloat = 56, pitch: CGFloat = 70
        var controls: [FaceControl] = []
        for number in 1...6 {
            let column = CGFloat((number - 1) % 3), row = CGFloat((number - 1) / 3)
            controls.append(FaceControl(id: "lcd_\(number)", kind: .key,
                                        frame: CGRect(x: p + column * pitch, y: p + row * pitch, width: key, height: key),
                                        label: "Key \(number) · \(number <= 3 ? "top" : "bottom") row"))
        }
        let gridBottom = p + pitch + key                      // 154
        let bigCentre = CGPoint(x: p + 2 * pitch + key + 40 + 52, y: p + (pitch + key) / 2)
        controls.append(FaceControl(id: "big", kind: .knob,
                                    frame: CGRect(x: bigCentre.x - 52, y: bigCentre.y - 52, width: 104, height: 104),
                                    label: "Big knob"))
        let rowCentreY = gridBottom + 48
        for number in 1...3 {
            let centreX = p + CGFloat(number - 1) * pitch + key / 2
            controls.append(FaceControl(id: "btn_\(number)", kind: .button,
                                        frame: CGRect(x: centreX - 20, y: rowCentreY - 20, width: 40, height: 40),
                                        label: "Button \(number)"))
        }
        for (index, id) in ["small_1", "small_2"].enumerated() {
            let centreX = bigCentre.x + (index == 0 ? -40 : 40)
            controls.append(FaceControl(id: id, kind: .knob,
                                        frame: CGRect(x: centreX - 26, y: rowCentreY - 26, width: 52, height: 52),
                                        label: "Small knob \(index + 1)"))
        }
        let width = bigCentre.x + 52 + p
        let height = rowCentreY + 26 + knobCaptionHeight + p
        return DeckFace(deck: .n3, size: CGSize(width: width, height: height), controls: controls)
    }()
}

/// Upright images of what a deck shows, for the config app's drawing, made by the same code that makes the deck's.
public enum DeckPreview {
    /// A key's icon as the deck shows it: trimmed, fitted with a 4 px margin on black, at the deck's key size.
    public static func keyImage(path: String, deck: DeckKind) -> CGImage? {
        let size = deck == .n4 ? IconImage.n4Size : 85
        return Canvas.iconTileImage(path: path, width: size, height: size)
    }

    /// A `picture` strip block, 176 × 112.
    public static func stripPicture(path: String) -> CGImage? {
        Canvas.iconTileImage(path: path, width: StripRenderer.width, height: StripRenderer.height)
    }

    /// A live strip block as drawn on the deck (JPEG, turned 180°), turned back upright.
    public static func upright(jpeg: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return Canvas.image(width: image.width, height: image.height) { ctx in
            ctx.translateBy(x: CGFloat(image.width), y: CGFloat(image.height))
            ctx.rotate(by: .pi)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
    }
}
