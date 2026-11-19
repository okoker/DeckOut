import Foundation
import Security
import Testing
@testable import DeckCore

// The code-signing requirements the app and the agent ask of each other.

@Test func requirementForms() {   // T-100
    // Signed with a Developer ID: the team, read from our own signature, and the peer's identifier.
    #expect(CodeSigning.requirement(peerIdentifier: "io.github.okoker.deckout", teamID: "ABCDE12345", peerCDHash: "ab12")
            == #"anchor apple generic and identifier "io.github.okoker.deckout" and certificate leaf[subject.OU] = "ABCDE12345""#)
    // Ad hoc: the exact binary, by its code hash.
    #expect(CodeSigning.requirement(peerIdentifier: "io.github.okoker.deckout.dev", teamID: nil, peerCDHash: "0123456789abcdef0123456789abcdef01234567")
            == #"identifier "io.github.okoker.deckout.dev" and cdhash H"0123456789abcdef0123456789abcdef01234567""#)
    // Neither: no requirement, and the caller refuses.
    #expect(CodeSigning.requirement(peerIdentifier: "io.github.okoker.deckout", teamID: nil, peerCDHash: nil) == nil)
    // Nothing that could break out of the quotes gets in.
    #expect(CodeSigning.requirement(peerIdentifier: #"x" or anchor apple"#, teamID: "ABCDE12345", peerCDHash: nil) == nil)
    #expect(CodeSigning.requirement(peerIdentifier: "x", teamID: #"A" or "B"#, peerCDHash: nil) == nil)
    #expect(CodeSigning.requirement(peerIdentifier: "x", teamID: nil, peerCDHash: "zz not hex") == nil)

    // What the app asks of the agent: the team when signed, else the agent's identifier.
    #expect(CodeSigning.agentRequirement(identity: .dev, teamID: nil)
            == #"identifier "io.github.okoker.deckout.dev.agent""#)
    #expect(CodeSigning.agentRequirement(identity: .release, teamID: "ABCDE12345")
            == #"anchor apple generic and identifier "io.github.okoker.deckout.agent" and certificate leaf[subject.OU] = "ABCDE12345""#)
}

@Test func cdhashPinsOneBinary() throws {   // T-101
    let ls = URL(fileURLWithPath: "/bin/ls")
    let hash = try #require(CodeSigning.cdhash(at: ls))
    #expect(hash.count == 40)
    #expect(hash.allSatisfy { $0.isHexDigit && !$0.isUppercase })

    func satisfies(_ requirement: String) throws -> Bool {
        var code: SecStaticCode?
        #expect(SecStaticCodeCreateWithPath(ls as CFURL, [], &code) == errSecSuccess)
        var req: SecRequirement?
        #expect(SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess)
        guard let code, let req else { return false }
        return SecStaticCodeCheckValidity(code, [], req) == errSecSuccess
    }
    let pinned = try #require(CodeSigning.requirement(peerIdentifier: "com.apple.ls", teamID: nil, peerCDHash: hash))
    #expect(try satisfies(pinned))
    let other = String(hash.dropLast()) + (hash.last == "0" ? "1" : "0")
    let wrong = try #require(CodeSigning.requirement(peerIdentifier: "com.apple.ls", teamID: nil, peerCDHash: other))
    #expect(try !satisfies(wrong))
}

@Test func readsOwnSignature() {   // part of T-101: the running process can describe itself
    #expect(CodeSigning.ownIdentifier() != nil)
    #expect(CodeSigning.ownCDHash()?.count == 40)
}
