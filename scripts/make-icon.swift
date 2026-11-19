// Draws DeckOut's app icon and writes Packaging/AppIcon.icns. Run by hand when the icon changes:
//   swift scripts/make-icon.swift Packaging/AppIcon.icns
// The icon: an N4-style deck (keys in colour, the strip, four knobs) on a blue macOS-style rounded square.
import AppKit
import CoreGraphics
import Foundation
import ImageIO

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ colors: [UInt32]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors.map { color($0) } as CFArray,
               locations: nil)!
}

/// The icon at 1024 × 1024 points, scaled to `pixels`. CG coordinates: y up.
func draw(pixels: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    ctx.interpolationQuality = .high

    // The rounded square (macOS grid: 824 on 1024, corner ~185), with a soft drop shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.35))
    ctx.addPath(tilePath)
    ctx.setFillColor(color(0x2F6BFF))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    ctx.drawLinearGradient(gradient([0x4D8DFF, 0x2457E6, 0x1A3BB0]), start: CGPoint(x: 512, y: 924),
                           end: CGPoint(x: 512, y: 100), options: [])
    // A faint light from the top.
    ctx.drawRadialGradient(CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                      colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)] as CFArray, locations: nil)!,
                           startCenter: CGPoint(x: 512, y: 900), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 900), endRadius: 620, options: [])
    ctx.restoreGState()

    // The deck, with its shadow.
    let deck = CGRect(x: 192, y: 262, width: 640, height: 500)
    let deckPath = CGPath(roundedRect: deck, cornerWidth: 64, cornerHeight: 64, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 50, color: color(0x000000, 0.5))
    ctx.addPath(deckPath)
    ctx.setFillColor(color(0x1B1B1D))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(deckPath)
    ctx.clip()
    ctx.drawLinearGradient(gradient([0x3A3A3D, 0x1E1E20, 0x141416]), start: CGPoint(x: deck.minX, y: deck.maxY),
                           end: CGPoint(x: deck.maxX, y: deck.minY), options: [])
    ctx.restoreGState()
    ctx.addPath(deckPath)
    ctx.setStrokeColor(color(0xFFFFFF, 0.10))
    ctx.setLineWidth(3)
    ctx.strokePath()

    // Two rows of five keys, lit like app icons.
    let keyColors: [[UInt32]] = [[0x0A84FF, 0x30D158, 0xFFD60A, 0xFF9F0A, 0xFF375F],
                                 [0xBF5AF2, 0x64D2FF, 0x5E5CE6, 0x32D74B, 0xFF453A]]
    let key: CGFloat = 84, pitch: CGFloat = 112
    let left = deck.minX + (deck.width - (4 * pitch + key)) / 2
    for row in 0..<2 {
        for column in 0..<5 {
            let rect = CGRect(x: left + CGFloat(column) * pitch, y: deck.maxY - 62 - key - CGFloat(row) * 108,
                              width: key, height: key)
            let path = CGPath(roundedRect: rect, cornerWidth: 16, cornerHeight: 16, transform: nil)
            ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: -5, dy: -5), cornerWidth: 20, cornerHeight: 20, transform: nil))
            ctx.setFillColor(color(0x000000))
            ctx.fillPath()
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            let c = keyColors[row][column]
            ctx.drawLinearGradient(gradient([c, c]), start: CGPoint(x: rect.midX, y: rect.maxY),
                                   end: CGPoint(x: rect.midX, y: rect.minY), options: [])
            ctx.drawLinearGradient(CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                              colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)] as CFArray,
                                              locations: nil)!,
                                   start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.midY),
                                   options: [])
            ctx.restoreGState()
        }
    }

    // The strip: one black panel, a blue gauge glowing on its right.
    let strip = CGRect(x: left - 2, y: deck.minY + 128, width: 4 * pitch + key + 4, height: 64)
    ctx.addPath(CGPath(roundedRect: strip.insetBy(dx: -5, dy: -5), cornerWidth: 18, cornerHeight: 18, transform: nil))
    ctx.setFillColor(color(0x000000))
    ctx.fillPath()
    ctx.setStrokeColor(color(0x2C2C2F))
    ctx.setLineWidth(3)
    for i in 1..<4 {
        let x = strip.minX + strip.width * CGFloat(i) / 4
        ctx.move(to: CGPoint(x: x, y: strip.minY + 6))
        ctx.addLine(to: CGPoint(x: x, y: strip.maxY - 6))
    }
    ctx.strokePath()
    ctx.setLineCap(.round)
    ctx.setLineWidth(7)
    let gauge = CGPoint(x: strip.maxX - strip.width / 8, y: strip.midY)
    ctx.setStrokeColor(color(0x3A3A3C))
    ctx.addArc(center: gauge, radius: 20, startAngle: 1.25 * .pi, endAngle: -0.25 * .pi, clockwise: true)
    ctx.strokePath()
    ctx.setStrokeColor(color(0x38BDF8))
    ctx.addArc(center: gauge, radius: 20, startAngle: 1.25 * .pi, endAngle: 0.35 * .pi, clockwise: true)
    ctx.strokePath()
    ctx.setFillColor(color(0x30D158))
    ctx.fill(CGRect(x: strip.minX + 22, y: strip.midY - 4, width: 60, height: 8))

    // Four knobs.
    for i in 0..<4 {
        let centre = CGPoint(x: strip.minX + strip.width * (CGFloat(i) + 0.5) / 4, y: deck.minY + 66)
        let r: CGFloat = 32
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 10, color: color(0x000000, 0.6))
        ctx.addEllipse(in: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r))
        ctx.setFillColor(color(0x2A2A2D))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r))
        ctx.clip()
        ctx.drawRadialGradient(gradient([0x6A6A6F, 0x2A2A2D, 0x111113]),
                               startCenter: CGPoint(x: centre.x - 10, y: centre.y + 12), startRadius: 0,
                               endCenter: centre, endRadius: r * 1.2, options: [])
        ctx.restoreGState()
    }
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest))
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Packaging/AppIcon.icns")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    writePNG(draw(pixels: points), to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    writePNG(draw(pixels: points * 2), to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
precondition(iconutil.terminationStatus == 0, "iconutil failed")
writePNG(draw(pixels: 512), to: FileManager.default.temporaryDirectory.appendingPathComponent("deckout-icon-512.png"))
print("Wrote \(output.path); preview at \(FileManager.default.temporaryDirectory.path)/deckout-icon-512.png")
