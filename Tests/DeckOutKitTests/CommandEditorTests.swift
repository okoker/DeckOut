import AppKit
import DeckCore
import SwiftUI
import Testing
@testable import DeckOutKit

/// An invented command shaped like the owner's iTerm one: long, with quotes inside quotes.
let longCommand = #"osascript -e 'tell application "iTerm2" to create window with profile "POPUP-INFO" command "/bin/zsh -lc \"/Users/someone/scripts/network-detail.sh --interface en0 --gateway 192.168.1.1 --watch --every 5; exec zsh\""'"#

// The command editor's text view keeps quotes and dashes as typed: macOS would otherwise turn ' " -- into curly
// quotes and a dash when the person's "smart quotes" setting is on, and the command would fail.
@MainActor @Test func codeTextViewKeepsWhatIsTyped() {   // T-153
    let view = CodeTextView.makeTextView()
    #expect(!view.isAutomaticQuoteSubstitutionEnabled)
    #expect(!view.isAutomaticDashSubstitutionEnabled)
    #expect(!view.isAutomaticTextReplacementEnabled)
    #expect(!view.isAutomaticSpellingCorrectionEnabled)
    #expect(!view.isContinuousSpellCheckingEnabled)
    #expect(!view.isRichText)
    #expect(view.font?.isFixedPitch == true)
    let typed = #"echo 'a' -- "b""#
    view.insertText(typed, replacementRange: NSRange(location: 0, length: 0))
    #expect(view.string == typed)
}

// The panel with a long command, and the larger editor: PNGs for a look.
@MainActor @Test func commandEditorsDraw() throws {   // T-154 (design check)
    #expect(longCommand.count > 200)
    var config = AppConfig.empty
    config.setButton(.n4, "key_3", ButtonConfig(action: "shell:" + longCommand))
    let model = try previewModel(config, deck: .n4, selection: "key_3")
    for dark in [false, true] {
        let png = try Snapshot.windowPNG(DeckStage(model: model, face: DeckFace.of(.n4)), size: MainWindow.size, dark: dark)
        #expect(png.count > 1000)
        try png.write(to: snapshotFolder.appendingPathComponent("editor-long-command-\(dark ? "dark" : "light").png"))
        let sheet = try Snapshot.windowPNG(CommandSheet(command: longCommand) { _ in }, size: CommandSheet.size, dark: dark)
        #expect(sheet.count > 1000)
        try sheet.write(to: snapshotFolder.appendingPathComponent("command-sheet-\(dark ? "dark" : "light").png"))
    }
}

/// Every `NSTextField` under `view`.
@MainActor private func textFields(in view: NSView) -> [NSTextField] {
    view.subviews.flatMap { ($0 as? NSTextField).map { [$0] } ?? [] + textFields(in: $0) }
}

// A multi-line field shows several lines at the panel's width. With the rounded-border style macOS draws it as one
// line, so a long command (or a two-line text icon) showed only its start (BL-026).
@MainActor @Test func multiLineFieldsShowSeveralLines() throws {   // T-160
    let field = CommitTextField(value: longCommand, placeholder: "", multiline: true, monospaced: true, lines: 3...10) { _ in }
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 264, height: 300), styleMask: [.borderless],
                          backing: .buffered, defer: false)
    let host = NSHostingView(rootView: field.frame(width: 264).frame(maxHeight: .infinity, alignment: .top))
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    let heights = textFields(in: host).map(\.frame.height)
    #expect(heights.max() ?? 0 > 40, "field heights \(heights)")   // one line is ~22 pt; three are ~45
}
