import AppKit
import DeckCore
import Foundation
import SwiftUI
import Testing
@testable import DeckOutKit

private func photoFile(width: Int, height: Int) throws -> String {
    let ctx = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.setFillColor(red: 0.9, green: 0.4, blue: 0.1, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("deckout-photo-\(UUID().uuidString).png").path
    let image = try #require(ctx.makeImage())
    let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: path))
    return path
}

private func n4Config() -> AppConfig {
    var config = AppConfig.empty
    config.ensureDeck(.n4)
    return config
}

@MainActor @Test func choosingCopiesAndChecks() throws {   // T-137
    let model = try previewModel(n4Config(), deck: .n4, selection: nil)
    let store = try #require(model.store)
    let source = try photoFile(width: 1600, height: 400)
    #expect(model.choosePhoto(source))
    let framing = try #require(model.lockPhoto)
    let folder = (store.path as NSString).deletingLastPathComponent
    #expect(framing.path.hasPrefix(folder + "/lock-photo-"))
    #expect(framing.zoom == 1 && framing.offsetX == 0 && framing.offsetY == 0)
    var st = stat()
    lstat(framing.path, &st)
    #expect(st.st_mode & 0o777 == 0o600)
    #expect(try ConfigFile.load(at: store.path).get().n4?.lockPhoto == framing)

    // Not a picture: a message; the config keeps its photo.
    let text = FileManager.default.temporaryDirectory.appendingPathComponent("deckout-\(UUID().uuidString).jpg").path
    try Data("nope".utf8).write(to: URL(fileURLWithPath: text))
    #expect(!model.choosePhoto(text))
    #expect(model.photoProblem != nil)
    #expect(model.lockPhoto == framing)
}

@MainActor @Test func framingIsClampedAndUndoable() throws {   // T-138
    let model = try previewModel(n4Config(), deck: .n4, selection: nil)
    let store = try #require(model.store)
    #expect(model.choosePhoto(try photoFile(width: 1600, height: 400)))
    // A drag: many moves, clamped at the photo's edge (0.66 for a 4:1 photo at zoom 1), one undo step.
    for step in 1...20 { model.setFraming(offsetX: Double(step) * 0.1, name: "Move Lock Photo") }
    #expect(abs((model.lockPhoto?.offsetX ?? 0) - 0.66) < 1e-6)
    #expect(model.lockPhoto?.offsetY == 0)
    store.undo()
    #expect(model.lockPhoto?.offsetX == 0)
    // Zoom stays 1…10.
    model.setFraming(zoom: 30, name: "Zoom Lock Photo")
    #expect(model.lockPhoto?.zoom == 10)
    model.resetFraming()
    #expect(model.lockPhoto?.zoom == 1 && model.lockPhoto?.offsetX == 0)
    // Remove, then undo brings it back.
    let path = model.lockPhoto?.path
    model.removePhoto()
    #expect(model.lockPhoto == nil)
    store.undo()
    #expect(model.lockPhoto?.path == path)
}

/// A test photo: sky, sun, hills (so the cut across the screens is easy to see).
private func scenicPhoto() throws -> String {
    let w = 1600, h = 1000
    let ctx = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let colors = [CGColor(red: 0.12, green: 0.23, blue: 0.54, alpha: 1), CGColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1)]
    let gradient = try #require(CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil))
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [])
    ctx.setFillColor(red: 1, green: 0.96, blue: 0.8, alpha: 1)
    ctx.fillEllipse(in: CGRect(x: 1000, y: 450, width: 220, height: 220))
    ctx.setFillColor(red: 0.26, green: 0.08, blue: 0.03, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: 260))
    let image = try #require(ctx.makeImage())
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("deckout-scene-\(UUID().uuidString).png").path
    let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: path))
    return path
}

@MainActor @Test func photoModeDraws() throws {   // T-138 (design check)
    let model = try previewModel(n4Config(), deck: .n4, selection: nil)
    #expect(model.choosePhoto(try scenicPhoto()))
    model.setFraming(zoom: 1.3, offsetY: 0.05, name: "Zoom Lock Photo")
    model.photoMode = true
    let view = HStack(spacing: 0) {
        PhotoStage(model: model)
        Divider()
        PhotoInspector(model: model).frame(width: 300)
    }
    for (hidden, dark) in [(false, false), (true, false), (true, true)] {
        model.showHiddenParts = hidden
        let png = try Snapshot.windowPNG(view, size: MainWindow.size, dark: dark)
        try png.write(to: snapshotFolder.appendingPathComponent("photo-\(hidden ? "hidden" : "plain")-\(dark ? "dark" : "light").png"))
    }
}
