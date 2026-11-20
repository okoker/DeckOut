import Foundation
import Testing
@testable import DeckCore

@Test func prefersTheBundledM1ddc() {   // T-147
    let app = URL(fileURLWithPath: "/Applications/DeckOut.app")
    let bundled = "/Applications/DeckOut.app/Contents/Helpers/m1ddc"
    // Inside DeckOut: its own copy, so no one installs anything.
    #expect(BrightnessControl.findM1DDC(bundleURL: app, executable: { _ in true }) == bundled)
    // Not there (a hand install, a build without it): Homebrew's, Apple Silicon first.
    #expect(BrightnessControl.findM1DDC(bundleURL: app, executable: { $0 != bundled }) == "/opt/homebrew/bin/m1ddc")
    #expect(BrightnessControl.findM1DDC(bundleURL: app, executable: { $0 == "/usr/local/bin/m1ddc" }) == "/usr/local/bin/m1ddc")
    #expect(BrightnessControl.findM1DDC(bundleURL: app, executable: { _ in false }) == nil)
}
