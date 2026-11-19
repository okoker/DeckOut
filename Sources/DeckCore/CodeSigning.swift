import Foundation
import Security

/// The code-signing requirements the app and the agent ask of each other over XPC.
///
/// - Signed with a Developer ID: the peer must carry our own team id (read from our signature at run time, so no
///   team id lives in the repo) and the expected identifier.
/// - Ad hoc (development): there is no team, so the agent pins the app's exact binary by its code hash, read from
///   the bundle on disk at each connection (a newly installed app is accepted by the old agent, which it then
///   restarts). The app checks the agent by identifier only: an impostor agent could feed the app a wrong status,
///   nothing more, while an impostor app could make the agent press keys.
public enum CodeSigning {

    // MARK: - Requirement strings

    /// Nil when there is neither a team nor a code hash to pin, or when an input could break out of its quotes.
    public static func requirement(peerIdentifier: String, teamID: String?, peerCDHash: String?) -> String? {
        guard isIdentifier(peerIdentifier) else { return nil }
        if let teamID {
            guard isTeamID(teamID) else { return nil }
            return #"anchor apple generic and identifier "\#(peerIdentifier)" and certificate leaf[subject.OU] = "\#(teamID)""#
        }
        if let peerCDHash {
            guard isHex(peerCDHash) else { return nil }
            return #"identifier "\#(peerIdentifier)" and cdhash H"\#(peerCDHash)""#
        }
        return nil
    }

    /// What the agent asks of a connecting app: the app in its own bundle (`bundleURL`, the agent's `Bundle.main`).
    public static func appRequirement(bundleURL: URL, identity: AppIdentity, teamID: String? = ownTeamID()) -> String? {
        requirement(peerIdentifier: identity.bundleID, teamID: teamID,
                    peerCDHash: teamID == nil ? cdhash(at: bundleURL) : nil)
    }

    /// What the app asks of the agent it connects to.
    public static func agentRequirement(identity: AppIdentity, teamID: String? = ownTeamID()) -> String {
        requirement(peerIdentifier: identity.agentLabel, teamID: teamID, peerCDHash: nil)
            ?? #"identifier "\#(identity.agentLabel)""#
    }

    // MARK: - Reading signatures

    public static func ownTeamID() -> String? { selfInfo()?[kSecCodeInfoTeamIdentifier as String] as? String }
    public static func ownIdentifier() -> String? { selfInfo()?[kSecCodeInfoIdentifier as String] as? String }
    public static func ownCDHash() -> String? { (selfInfo()?[kSecCodeInfoUnique as String] as? Data).map(hex) }

    /// The code hash of the bundle or executable at `url`, lowercase hex; nil when it isn't signed.
    public static func cdhash(at url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        return (info(code)?[kSecCodeInfoUnique as String] as? Data).map(hex)
    }

    // MARK: - Private

    private static func selfInfo() -> [String: Any]? {
        var running: SecCode?
        guard SecCodeCopySelf([], &running) == errSecSuccess, let running else { return nil }
        var code: SecStaticCode?
        guard SecCodeCopyStaticCode(running, [], &code) == errSecSuccess, let code else { return nil }
        return info(code)
    }

    private static func info(_ code: SecStaticCode) -> [String: Any]? {
        var dict: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &dict) == errSecSuccess
        else { return nil }
        return dict as? [String: Any]
    }

    private static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    private static func isIdentifier(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_") }
    }
    private static func isTeamID(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
    }
    private static func isHex(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isASCII && $0.isHexDigit }
    }
}
