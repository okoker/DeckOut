import Foundation
import Testing
@testable import DeckCore

// Everything that names DeckOut on disk and in launchd comes from the bundle id, in one place.

@Test func derivesNamesFromBundleID() throws {
    let release = try #require(AppIdentity(bundleID: "io.github.okoker.deckout"))
    #expect(release == .release)
    #expect(!release.isDev)
    #expect(release.appName == "DeckOut")
    #expect(release.agentLabel == "io.github.okoker.deckout.agent")
    #expect(release.agentPlistName == "io.github.okoker.deckout.agent.plist")
    #expect(release.configPath(home: "/Users/x") == "/Users/x/.deckout/config.json")
    #expect(release.configFolderForPeople == "~/.deckout")
    #expect(release.logFolder(home: "/Users/x") == "/Users/x/Library/Logs/DeckOut")

    let dev = try #require(AppIdentity(bundleID: "io.github.okoker.deckout.dev"))
    #expect(dev == .dev)
    #expect(dev.isDev)
    #expect(dev.appName == "DeckOut Dev")
    #expect(dev.agentLabel == "io.github.okoker.deckout.dev.agent")
    #expect(dev.agentPlistName == "io.github.okoker.deckout.dev.agent.plist")
    #expect(dev.configPath(home: "/Users/x") == "/Users/x/.deckout-dev/config.json")
    #expect(dev.configFolderForPeople == "~/.deckout-dev")
    #expect(dev.logFolder(home: "/Users/x") == "/Users/x/Library/Logs/DeckOut Dev")
    #expect(AppIdentity.helperName == "DeckOutAgent")
}

@Test func unknownBundleIsNotDeckOut() {
    #expect(AppIdentity(bundleID: "com.streamdeck.controller") == nil)
    #expect(AppIdentity(bundleID: nil) == nil)
    #expect(AppIdentity(bundleID: "io.github.okoker.deckout.agent") == nil)
    #expect(AppIdentity(bundleID: "") == nil)
}
