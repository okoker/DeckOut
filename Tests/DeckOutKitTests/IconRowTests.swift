import AppKit
import DeckCore
import SwiftUI
import Testing
@testable import DeckOutKit

/// `view` in a real (offscreen) window, laid out: its AppKit controls can be found and clicked.
@MainActor private func host<V: View>(_ view: V, width: CGFloat = 300) -> (NSWindow, NSView) {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 400), styleMask: [.titled],
                          backing: .buffered, defer: false)
    let host = NSHostingView(rootView: view.frame(width: width))
    window.contentView = host
    window.orderFront(nil)
    host.layoutSubtreeIfNeeded()
    return (window, host)
}

/// The segmented control under `view` that has a segment labelled `label`.
@MainActor private func segments(with label: String, in view: NSView) -> NSSegmentedControl? {
    if let control = view as? NSSegmentedControl,
       (0..<control.segmentCount).contains(where: { control.label(forSegment: $0) == label }) { return control }
    return view.subviews.lazy.compactMap { segments(with: label, in: $0) }.first
}

/// Clicks the segment labelled `label`, as a person would, and lets SwiftUI catch up.
@MainActor private func click(_ label: String, in control: NSSegmentedControl) {
    control.selectedSegment = (0..<control.segmentCount).first { control.label(forSegment: $0) == label } ?? -1
    _ = control.sendAction(control.action, to: control.target)
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
}

// Choosing Library opens the symbols without changing the key: it used to put a star on it at once, so looking and
// closing the popover left the star (BL-022). The key keeps its text icon until a symbol is clicked; the click
// writes that symbol, in Fill on the library's dark grey (a symbol tile already on the key keeps its colours).
@MainActor @Test func libraryWritesNothingUntilASymbolIsClicked() throws {   // T-181
    let model = try previewModel(AppConfig.empty, deck: .n4, selection: "key_3")
    let text = IconTile(kind: .text, text: "Notes", symbol: nil, style: nil, background: IconRow.swatches[0],
                        foreground: nil)
    var written: [IconTile] = []
    let (window, view) = host(IconRow(model: model, shape: .key(.n4), choice: .nothing, icon: "/tmp/tile.png",
                                      tile: text, setIcon: { _ in }, setTile: { written.append($0) }))
    defer { window.orderOut(nil) }
    let source = try #require(segments(with: "Library", in: view))
    click("Library", in: source)
    #expect(written.isEmpty, "choosing Library wrote \(written)")
    let popover = (window.childWindows ?? []).first { $0.isVisible && "\(type(of: $0))".contains("Popover") }
    #expect(popover != nil, "the symbols are open")

    let picked = IconRow.symbolTile(text, name: "house", style: "fill")
    #expect(picked == IconTile(kind: .symbol, text: nil, symbol: "house", style: "fill",
                               background: IconRow.swatches[9], foreground: nil))
    let blue = IconTile(kind: .symbol, text: nil, symbol: "star", style: "bold", background: "#0A84FF",
                        foreground: "#FFFFFF")
    #expect(IconRow.symbolTile(blue, name: "house", style: "fill")
            == IconTile(kind: .symbol, text: nil, symbol: "house", style: "fill", background: "#0A84FF",
                        foreground: "#FFFFFF"))
}

// Bold / Fill restyles the symbol already on the key at once: it used to change only the picker's grid, so the key
// stayed as it was until a symbol was clicked again (BL-022). With no symbol chosen yet it writes nothing.
@MainActor @Test func boldOrFillRestylesTheChosenSymbol() throws {   // T-182
    var picks: [String] = []
    let (window, view) = host(SymbolPicker(library: nil, selected: "star", style: "fill") { picks.append("\($0) \($1)") },
                              width: 360)
    defer { window.orderOut(nil) }
    click("Bold", in: try #require(segments(with: "Bold", in: view)))
    #expect(picks == ["star bold"])

    var none: [String] = []
    let (other, otherView) = host(SymbolPicker(library: nil, selected: nil, style: "fill") { none.append("\($0) \($1)") },
                                  width: 360)
    defer { other.orderOut(nil) }
    click("Bold", in: try #require(segments(with: "Bold", in: otherView)))
    #expect(none.isEmpty)
}
