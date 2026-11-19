import Foundation
import Testing
@testable import DeckCore

@Test func parsesEveryKind() throws {                               // T-082
    let table: [(String, ActionKind)] = [
        ("none", .none),
        ("shell:open -a Notes", .shell("open -a Notes")),
        ("key:cmd+space", .key("cmd+space")),
        ("app:/Applications/Notes.app", .app("/Applications/Notes.app")),
        ("url:http://localhost:8080/x", .url(try #require(URL(string: "http://localhost:8080/x")))),
        ("open:/Users/someone/Documents", .open("/Users/someone/Documents")),
        ("script:/Users/someone/bin/run me.sh", .script("/Users/someone/bin/run me.sh")),
        ("shortcut:Show Hello", .shortcut("Show Hello")),
        ("media_play_pause", .media(.playPause)),
        ("media_next", .media(.next)),
        ("media_previous", .media(.previous)),
    ] + LockPolicy.builtIns.map { ($0, ActionKind.builtIn($0)) }
    for (action, kind) in table {
        #expect(ActionKind.parse(action) == kind, "\(action)")
    }

    guard case .url(let url) = ActionKind.parse("url:https://example.com/a/b?c=1#d") else {
        Issue.record("not a url")
        return
    }
    #expect(url.absoluteString == "https://example.com/a/b?c=1#d")
    #expect(url.path == "/a/b")
    #expect(url.query == "c=1")
    #expect(url.fragment == "d")
}

@Test func badPayloadsAreInvalid() {                                // T-083
    for action in ["app:Notes.app", "app:/Applications/Notes", "url:ftp://x", "url:notaurl", "open:relative",
                   "script:", "shortcut:", "frobnicate"] {
        guard case .invalid(let reason) = ActionKind.parse(action) else {
            Issue.record("\(action) parsed as \(ActionKind.parse(action))")
            continue
        }
        #expect(!reason.isEmpty, "\(action)")
    }
}
