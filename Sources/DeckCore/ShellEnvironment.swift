import Foundation

/// Whether the user's shell environment was read, for `status` and the log.
public struct EnvironmentStatus: Codable, Equatable {
    public var state: ShellEnvironment.State
    public var detail: String?

    public init(state: ShellEnvironment.State, detail: String?) {
        self.state = state
        self.detail = detail
    }
}

/// The environment `shell:`, `script:` and `shortcut:` actions run with: the user's own, as their login shell sets
/// it up, so a command finds what it finds in Terminal (Homebrew tools, nvm, …). launchd starts the daemon with a
/// bare PATH (`/usr/bin:/bin:/usr/sbin:/sbin`), which is why `arp-scan` wasn't found.
///
/// `refresh` starts the login shell as login + interactive (so `.zprofile` and `.zshrc` both run), prints the
/// environment between two random markers, and keeps what is between them: anything the startup files print
/// lands outside. A shell that hangs, waits for input or prints no markers falls back to the daemon's own
/// environment with `/opt/homebrew/bin` and `/usr/local/bin` added to PATH. Prior art: VS Code,
/// `src/vs/platform/shell/node/shellEnv.ts:70, 109-155`.
public final class ShellEnvironment {
    public enum State: String, Codable {
        case resolving, resolved
        case fellBack = "fell_back"
    }

    private let shell: String?            // nil: fixed (tests); refresh does nothing
    private let timeout: TimeInterval
    private let base: [String: String]
    private let queue = DispatchQueue(label: "deckcore.shell-environment", qos: .utility)

    private let lock = NSLock()
    private var _current: [String: String]
    private var _state: State
    private var _detail: String?
    private var everResolved = false

    public init(shell: String = ShellEnvironment.loginShell(), timeout: TimeInterval = 10,
                base: [String: String] = ProcessInfo.processInfo.environment) {
        self.shell = shell
        self.timeout = timeout
        self.base = base
        _current = Self.fallback(base: base)
        _state = .resolving
    }

    /// A fixed environment that `refresh` leaves alone (tests).
    public init(fixed: [String: String]) {
        shell = nil
        timeout = 0
        base = fixed
        _current = fixed
        _state = .resolved
    }

    /// The environment to run commands with: the fallback until the first refresh finishes.
    public var current: [String: String] { lock.lock(); defer { lock.unlock() }; return _current }
    public var state: State { lock.lock(); defer { lock.unlock() }; return _state }
    public var detail: String? { lock.lock(); defer { lock.unlock() }; return _detail }
    public var status: EnvironmentStatus {
        lock.lock(); defer { lock.unlock() }
        return EnvironmentStatus(state: _state, detail: _detail)
    }

    /// Reads the environment from the login shell, off the main thread. `completion` runs on a background queue.
    /// When a later read fails, the environment from the last good read stays in use (reported as fell back).
    public func refresh(completion: (() -> Void)? = nil) {
        guard let shell else { completion?(); return }
        queue.async { [self] in
            let marker = UUID().uuidString
            let command = "printf '%s' '\(marker)'; /usr/bin/env -0; printf '%s' '\(marker)'"
            let captured = ProcessRunner.capture(executable: shell, arguments: ["-l", "-i", "-c", command],
                                                 environment: base, timeout: timeout, cap: 1 << 20)
            let parsed = Self.parse(captured.stdout, marker: marker)
            lock.lock()
            if let parsed {
                _current = parsed
                _state = .resolved
                _detail = nil
                everResolved = true
            } else {
                let why = captured.error
                    ?? captured.exitStatus.flatMap { $0 != 0 ? "the shell exited with status \($0)" : nil }
                    ?? "no environment in the shell's output"
                if !everResolved { _current = Self.fallback(base: base) }
                _state = .fellBack
                _detail = everResolved ? "\(why); still using the last environment read" : why
            }
            lock.unlock()
            completion?()
        }
    }

    /// `base` with Homebrew's two folders added to the end of PATH (each once).
    public static func fallback(base: [String: String]) -> [String: String] {
        var environment = base
        let path = base["PATH"].flatMap { $0.isEmpty ? nil : $0 } ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        var parts = path.split(separator: ":").map(String.init)
        for extra in ["/opt/homebrew/bin", "/usr/local/bin"] where !parts.contains(extra) {
            parts.append(extra)
        }
        environment["PATH"] = parts.joined(separator: ":")
        return environment
    }

    /// The `env -0` output between the first two `marker`s, or nil when they or any variable are missing.
    public static func parse(_ output: Data, marker: String) -> [String: String]? {
        let mark = Data(marker.utf8)
        guard let first = output.range(of: mark),
              let second = output.range(of: mark, in: first.upperBound..<output.endIndex) else { return nil }
        var environment: [String: String] = [:]
        for entry in output[first.upperBound..<second.lowerBound].split(separator: 0) {
            guard let equals = entry.firstIndex(of: UInt8(ascii: "=")), equals != entry.startIndex else { continue }
            let name = String(decoding: entry[entry.startIndex..<equals], as: UTF8.self)
            environment[name] = String(decoding: entry[entry.index(after: equals)...], as: UTF8.self)
        }
        return environment.isEmpty ? nil : environment
    }

    /// The user's login shell from the user database, else `/bin/zsh`.
    public static func loginShell() -> String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return "/bin/zsh"
    }
}
