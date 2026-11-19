import Foundation

/// Images for the N4 touch strip: four separate 176×112 JPEG blocks, each turned 180°.
enum StripRenderer {
    static let width = 176
    static let height = 112

    /// A black tile.
    static func blank(w: Int = width, h: Int = height) -> Data {
        Canvas.jpeg(width: w, height: h) { _ in } ?? Data()
    }

    /// A `picture` block: the image at `path`, fitted inside a 4 px margin. Nil if unreadable.
    static func picture(path: String) -> Data? {
        Canvas.iconTile(path: path, width: width, height: height)
    }

    // MARK: - Volume

    static let gaugeCenter = (x: 88, y: 56)     // upright coordinates, y up
    static let gaugeRadius = 42
    private static let gaugeLineWidth: CGFloat = 10
    private static let gaugeStart: CGFloat = 225 * .pi / 180     // 7:30, sweeping clockwise…
    private static let gaugeSweep: CGFloat = 270 * .pi / 180     // …to 4:30, open at the bottom

    private static let textColor = Canvas.color(0xF5F5F7)
    private static let dimText = Canvas.color(0x8E8E93)
    private static let track = Canvas.color(0x3A3A3C)
    private static let accent = Canvas.color(0x38BDF8)
    private static let mutedRed = Canvas.color(0xFF6B6B)

    /// System volume as a gauge: the arc fills with the level, the number sits inside.
    /// Muted: grey arc and "MUTE". `percent` nil (no output device): "–".
    static func volume(percent: Int?, muted: Bool) -> Data {
        let center = CGPoint(x: gaugeCenter.x, y: gaugeCenter.y)
        let radius = CGFloat(gaugeRadius)
        let level = CGFloat(min(100, max(0, percent ?? 0))) / 100
        return Canvas.jpeg(width: width, height: height) { ctx in
            ctx.setLineWidth(gaugeLineWidth)
            ctx.setLineCap(.round)
            ctx.setStrokeColor(track)
            ctx.addArc(center: center, radius: radius, startAngle: gaugeStart,
                       endAngle: gaugeStart - gaugeSweep, clockwise: true)
            ctx.strokePath()
            if !muted, percent != nil, level > 0 {
                ctx.setStrokeColor(accent)
                ctx.addArc(center: center, radius: radius, startAngle: gaugeStart,
                           endAngle: gaugeStart - gaugeSweep * level, clockwise: true)
                ctx.strokePath()
            }

            if muted {
                Canvas.drawText("MUTE", in: ctx, center: CGPoint(x: center.x, y: center.y + 6),
                                font: Canvas.font(size: 20, weight: .heavy), color: mutedRed)
                if let percent {
                    Canvas.drawText("\(percent)%", in: ctx, center: CGPoint(x: center.x, y: center.y - 16),
                                    font: Canvas.font(size: 14, weight: .semibold), color: dimText)
                }
            } else if let percent {
                Canvas.drawText([("\(percent)", Canvas.font(size: 34, weight: .bold), textColor),
                                 ("%", Canvas.font(size: 16, weight: .semibold), dimText)],
                                in: ctx, center: CGPoint(x: center.x, y: center.y + 2))
            } else {
                Canvas.drawText("–", in: ctx, center: center, font: Canvas.font(size: 34), color: dimText)
            }
            Canvas.drawText("VOL", in: ctx, center: CGPoint(x: center.x, y: 12),
                            font: Canvas.font(size: 12, weight: .semibold), color: dimText)
        } ?? blank()
    }
}
