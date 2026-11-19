import CoreGraphics
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

    // MARK: - Load

    private static func color(_ c: LoadColour?) -> CGColor {
        switch c {
        case .green?: return Canvas.color(0x30D158)
        case .amber?: return Canvas.color(0xFFB340)
        case .red?:   return Canvas.color(0xFF453A)
        case nil:     return textColor
        }
    }

    /// CPU and memory side by side, each a number over a small level bar, coloured on its own
    /// (CPU by its value, memory by macOS's pressure level). A missing figure shows "–".
    static func load(cpu: Int?, mem: Int?, memLevel: PressureLevel?) -> Data {
        let columns: [(label: String, value: Int?, colour: LoadColour?)] = [
            ("CPU", cpu, cpu.map(LoadColour.cpu)),
            ("MEM", mem, mem == nil ? nil : memLevel.map(LoadColour.memory)),
        ]
        return Canvas.jpeg(width: width, height: height) { ctx in
            ctx.setFillColor(track)
            ctx.fill(CGRect(x: 87, y: 14, width: 2, height: 84))     // divider
            for (i, column) in columns.enumerated() {
                let midX = CGFloat(44 + 88 * i)
                let ink = color(column.colour)
                if let value = column.value {
                    Canvas.drawText([("\(value)", Canvas.font(size: 30, weight: .bold), ink),
                                     ("%", Canvas.font(size: 14, weight: .semibold), dimText)],
                                    in: ctx, center: CGPoint(x: midX, y: 68))
                } else {
                    Canvas.drawText("–", in: ctx, center: CGPoint(x: midX, y: 68),
                                    font: Canvas.font(size: 30), color: dimText)
                }
                let bar = CGRect(x: midX - 30, y: 38, width: 60, height: 6)
                ctx.setFillColor(track)
                ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 3, cornerHeight: 3, transform: nil))
                ctx.fillPath()
                if let value = column.value, value > 0 {
                    let fill = CGRect(x: bar.minX, y: bar.minY, width: bar.width * CGFloat(min(value, 100)) / 100,
                                      height: bar.height)
                    ctx.setFillColor(ink)
                    ctx.addPath(CGPath(roundedRect: fill, cornerWidth: 3, cornerHeight: 3, transform: nil))
                    ctx.fillPath()
                }
                Canvas.drawText(column.label, in: ctx, center: CGPoint(x: midX, y: 18),
                                font: Canvas.font(size: 12, weight: .semibold), color: dimText)
            }
        } ?? blank()
    }

    // MARK: - Internet

    /// How a latency shows: one decimal below 10 ms, whole ms above.
    static func latencyFigure(_ ms: Double) -> String {
        ms < 10 ? String(format: "%.1f", ms) : "\(Int(ms.rounded()))"
    }

    /// Latency in ms with a big arrow behind it (red ▲ rose, green ▼ fell). No reply: the whole block red.
    static func internet(ms: Double?, trend: Trend, failed: Bool) -> Data {
        Canvas.jpeg(width: width, height: height) { ctx in
            let white = Canvas.color(0xFFFFFF)
            if failed {
                ctx.setFillColor(Canvas.color(0xD32F2F))
                ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
                Canvas.drawText("NO REPLY", in: ctx, center: CGPoint(x: 88, y: 62),
                                font: Canvas.font(size: 22, weight: .heavy), color: white)
                Canvas.drawText("PING", in: ctx, center: CGPoint(x: 88, y: 18),
                                font: Canvas.font(size: 12, weight: .semibold), color: white)
                return
            }
            if trend != .none {
                let up = trend == .up
                let (apex, base): (CGFloat, CGFloat) = up ? (106, 8) : (6, 104)
                ctx.setFillColor(up ? Canvas.color(0xFF453A) : Canvas.color(0x30D158))
                ctx.setAlpha(0.45)
                ctx.move(to: CGPoint(x: 88, y: apex))
                ctx.addLine(to: CGPoint(x: 26, y: base))
                ctx.addLine(to: CGPoint(x: 150, y: base))
                ctx.closePath()
                ctx.fillPath()
                ctx.setAlpha(1)
            }
            if let ms {
                let figure = latencyFigure(ms)
                Canvas.drawText([(figure, Canvas.font(size: 38, weight: .bold), textColor),
                                 ("ms", Canvas.font(size: 15, weight: .semibold), dimText)],
                                in: ctx, center: CGPoint(x: 88, y: 60))
            } else {
                Canvas.drawText("–", in: ctx, center: CGPoint(x: 88, y: 60), font: Canvas.font(size: 38), color: dimText)
            }
            Canvas.drawText("PING", in: ctx, center: CGPoint(x: 88, y: 18),
                            font: Canvas.font(size: 12, weight: .semibold), color: dimText)
        } ?? blank()
    }
}
