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
        return arguments.first == "print" ? 113 : 0          // stopped: launchd no longer has it
    }
    #expect(calls == [["bootout", "gui/501", plist], ["print", "gui/501/com.streamdeck.controller"]])
    #expect(!FileManager.default.fileExists(atPath: plist))
    #expect(FileManager.default.contents(atPath: plist + ".retired-by-deckout") == Data("<plist/>".utf8))
    #expect(OldController.find(home: home) == nil)

    // Not running (bootout fails): still moved aside, so it won't start at the next login.
    try Data("<plist/>".utf8).write(to: URL(fileURLWithPath: plist))
    try OldController.retire(home: home, uid: 501) { arguments in arguments.first == "print" ? 113 : 3 }
    #expect(OldController.find(home: home) == nil)
}

@Test func retiringIsSafe() throws {   // T-146 (review M1, M2)
    let home = try fakeHome()
    let plist = home + "/Library/LaunchAgents/com.streamdeck.controller.plist"
    try Data("<plist/>".utf8).write(to: URL(fileURLWithPath: plist))
    // Stopped by its plist, then checked: still loaded → a problem, and nothing is moved.
    var calls: [[String]] = []
    #expect(throws: OldController.RetireError.self) {
        try OldController.retire(home: home, uid: 501) { args in
            calls.append(args)
            return args.first == "print" ? 0 : 5          // bootout failed; print finds it loaded
        }
    }
    #expect(calls.first == ["bootout", "gui/501", plist])
    #expect(FileManager.default.fileExists(atPath: plist))

    // Retired once; a second Retire It (a double click) leaves the kept copy alone.
    try OldController.retire(home: home, uid: 501) { args in args.first == "print" ? 113 : 0 }
    #expect(FileManager.default.fileExists(atPath: plist + ".retired-by-deckout"))
    try OldController.retire(home: home, uid: 501) { args in args.first == "print" ? 113 : 0 }
    #expect(FileManager.default.fileExists(atPath: plist + ".retired-by-deckout"))
}
