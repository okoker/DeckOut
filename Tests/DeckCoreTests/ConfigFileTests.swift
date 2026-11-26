import Foundation
import Testing
@testable import DeckCore

// Every test works in its own fresh temporary folder; nothing touches ~/.deckout.

private func freshFolder() throws -> String {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("deckcore-config-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.path
}

private func write(_ text: String, to path: String, mode: mode_t) throws {
    try Data(text.utf8).write(to: URL(fileURLWithPath: path))
    #expect(chmod(path, mode) == 0)
}

private func mode(of path: String) -> mode_t {
    var st = stat()
    _ = lstat(path, &st)
    return st.st_mode & 0o777
}

private let sample = AppConfig(
    displays: [DisplayConfig(name: "Left", serial: "S1")],
    n4: N4Section(brightness: 60, swipe: nil, lockPhoto: nil,
                  presets: [N4Preset(name: "Work", keys: ["key_1": ButtonConfig(action: "shell:open -a Notes")],
                                     strip: ["1": StripBlockConfig(type: .volume)])],
                  activePreset: "Work"))

@Test func saveWritesAtomicallyWithMode600() throws {               // T-069
    let folder = try freshFolder()
    let path = folder + "/config.json"
    try ConfigFile.save(sample, to: path)
    #expect(mode(of: path) == 0o600)
    #expect(ConfigFile.securityProblem(at: path) == nil)
    #expect(try ConfigFile.load(at: path).get() == sample)
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder) == ["config.json"])   // no temp file left
}

@Test func saveCreatesAMissingFolderPrivately() throws {            // part of T-069
    let folder = try freshFolder() + "/deckout"
    try ConfigFile.save(sample, to: folder + "/config.json")
    #expect(mode(of: folder) == 0o700)
}

@Test func firstSaveKeepsABackupOnce() throws {                     // T-070
    let folder = try freshFolder()
    let path = folder + "/config.json", backup = path + ".before-app"
    try write("X", to: path, mode: 0o600)
    try ConfigFile.save(sample, to: path)
    #expect(try String(contentsOfFile: backup, encoding: .utf8) == "X")
    #expect(mode(of: backup) == 0o600)
    try ConfigFile.save(sample, to: path)
    #expect(try String(contentsOfFile: backup, encoding: .utf8) == "X")

    let other = try freshFolder() + "/config.json"
    try ConfigFile.save(sample, to: other)
    #expect(!FileManager.default.fileExists(atPath: other + ".before-app"))
}

@Test func firstSaveKeepsTheRollbackCopy() throws {                 // T-201
    // DeckOut 2.1.0 can't read knobs in presets: the first save by 2.2 keeps the file as it was, once, so going back
    // is a restore. A `.before-app` from an earlier app save doesn't stop it.
    let folder = try freshFolder()
    let path = folder + "/config.json", copy = path + ConfigFile.rollbackSuffix
    #expect(ConfigFile.rollbackSuffix == ".before-2.2")
    try write("2.1.0 file", to: path, mode: 0o600)
    try write("1.0 file", to: path + ".before-app", mode: 0o600)
    try ConfigFile.save(sample, to: path)
    #expect(try String(contentsOfFile: copy, encoding: .utf8) == "2.1.0 file")
    #expect(mode(of: copy) == 0o600)
    var changed = sample
    changed.n4?.brightness = 20
    try ConfigFile.save(changed, to: path)
    #expect(try String(contentsOfFile: copy, encoding: .utf8) == "2.1.0 file")

    let other = try freshFolder() + "/config.json"
    try ConfigFile.save(sample, to: other)
    #expect(!FileManager.default.fileExists(atPath: other + ConfigFile.rollbackSuffix))
}

@Test func securityProblemsAreReported() throws {                   // T-071
    let folder = try freshFolder()
    let real = folder + "/real.json", link = folder + "/link.json", open = folder + "/open.json"
    try write("{}", to: real, mode: 0o600)
    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)
    try write("{}", to: open, mode: 0o666)
    #expect(ConfigFile.securityProblem(at: link) != nil)
    #expect(ConfigFile.securityProblem(at: open) != nil)
    #expect(ConfigFile.securityProblem(at: folder + "/missing.json") != nil)
    #expect(ConfigFile.securityProblem(at: real) == nil)
}

@Test func startupWithoutAUsableConfigRunsBlank() throws {          // T-072
    let folder = try freshFolder()
    let missing = folder + "/missing.json", broken = folder + "/broken.json", open = folder + "/open.json"
    try write("{ not json", to: broken, mode: 0o600)
    try write(String(decoding: try sample.encoded(), as: UTF8.self), to: open, mode: 0o666)

    let noFile = ConfigFile.startupConfig(at: missing)
    #expect(noFile.config == .empty)
    #expect(noFile.problem == "No config yet at \(missing)")

    let unparseable = ConfigFile.startupConfig(at: broken)
    #expect(unparseable.config == .empty)
    #expect(unparseable.problem?.contains("doesn't load") == true)

    let writable = ConfigFile.startupConfig(at: open)
    #expect(writable.config == .empty)
    #expect(writable.problem?.contains("writable") == true)
}

@Test func resolvePathPrefersFlagThenExistingThenDefault() {        // T-073
    let home = "/Users/someone", exec = "/opt/deck"
    let homeConfig = home + "/.deckout/config.json", execConfig = exec + "/config.json"
    func resolve(_ arguments: [String], existing: Set<String>) -> String? {
        ConfigFile.resolvePath(arguments: arguments, home: home, execDir: exec, exists: { existing.contains($0) })
    }
    #expect(resolve(["deck", "--config", "/x"], existing: [homeConfig]) == "/x")
    #expect(resolve(["deck"], existing: [homeConfig, execConfig]) == homeConfig)
    #expect(resolve(["deck"], existing: [execConfig]) == execConfig)
    #expect(resolve(["deck"], existing: []) == homeConfig)
    #expect(resolve(["deck", "--config"], existing: [homeConfig]) == nil)
}

@Test func saveRefusesWhatDoesNotRoundTrip() throws {               // T-119
    // A config the agent would refuse to load (zoom outside 1…10) is never written: the file stays as it was.
    let folder = try freshFolder()
    let path = folder + "/config.json"
    try ConfigFile.save(sample, to: path)
    var bad = sample
    bad.n4?.lockPhoto = LockPhotoConfig(path: "/p.jpg", zoom: 20)
    #expect(throws: ConfigFile.SaveError.self) { try ConfigFile.save(bad, to: path) }
    #expect(try ConfigFile.load(at: path).get() == sample)
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder).sorted() == ["config.json"])
}
