import DeckCore
import Testing
@testable import DeckOutKit

@Test func onlyFromApplications() {   // T-113
    #expect(AppLocation.problem(bundlePath: "/Applications/DeckOut.app", identity: .release) == nil)
    #expect(AppLocation.problem(bundlePath: "/Applications/DeckOut.app/", identity: .release) == nil)
    // Downloads, a translocated copy (opened straight from a download), a subfolder, a renamed copy: refused.
    for path in ["/Users/x/Downloads/DeckOut.app",
                 "/private/var/folders/ab/xyz/T/AppTranslocation/1234-5678/d/DeckOut.app",
                 "/Applications/Utilities/DeckOut.app",
                 "/Applications/DeckOut 2.app",
                 "/Volumes/DeckOut/DeckOut.app"] {
        #expect(AppLocation.problem(bundlePath: path, identity: .release) != nil, "\(path)")
    }
    // The dev variant runs from anywhere.
    #expect(AppLocation.problem(bundlePath: "/Users/x/Applications/DeckOut Dev.app", identity: .dev) == nil)
}
