import Foundation
import Testing
@testable import DeckOutKit

private func fakeHome() throws -> String {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("deckout-home-\(UUID().uuidString)").path
    try FileManager.default.createDirectory(atPath: home + "/Library/LaunchAgents", withIntermediateDirectories: true)
    return home
}

@Test func findsAndRetiresReversibly() throws {   // T-146
    let home = try fakeHome()
    #expect(OldController.find(home: home) == nil)
    let plist = home + "/Library/LaunchAgents/com.streamdeck.controller.plist"
    try Data("<plist/>".utf8).write(to: URL(fileURLWithPath: plist))
    #expect(OldController.find(home: home) == plist)

    // Retire: launchd stops it, the plist moves aside (kept for rollback), the program is left alone.
    var calls: [[String]] = []
    try OldController.retire(home: home, uid: 501) { arguments in
        calls.append(arguments)
        return 0
    }
    #expect(calls == [["bootout", "gui/501/com.streamdeck.controller"]])
    #expect(!FileManager.default.fileExists(atPath: plist))
    #expect(FileManager.default.contents(atPath: plist + ".retired-by-deckout") == Data("<plist/>".utf8))
    #expect(OldController.find(home: home) == nil)

    // Not running (bootout fails): still moved aside, so it won't start at the next login.
    try Data("<plist/>".utf8).write(to: URL(fileURLWithPath: plist))
    try OldController.retire(home: home, uid: 501) { _ in 3 }
    #expect(OldController.find(home: home) == nil)
}
