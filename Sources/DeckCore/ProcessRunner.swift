import Foundation

/// What running an action produced, for the log and the config app's Test button. `exitStatus` is nil when the
/// program never started or was ended by a signal; `error` then says why.
public struct ActionResult: Codable, Equatable {
    public var exitStatus: Int32?
    public var stdout: String
    public var stderr: String
    public var error: String?

    public init(exitStatus: Int32? = nil, stdout: String = "", stderr: String = "", error: String? = nil) {
        self.exitStatus = exitStatus
        self.stdout = stdout
        self.stderr = stderr
        self.error = error
    }
}

/// The one way the daemon runs a program: `shell:` commands, scripts, Shortcuts and the shell-environment read.
///
/// - Arguments go to the program as an array, never through a shell string, so paths with spaces, quotes or `$`
///   arrive as given.
/// - stdin is `/dev/null`: a program that waits for input gets end-of-file at once instead of hanging.
/// - stdout and stderr are drained as they arrive (a full pipe would stall the program) and each is capped.
/// - The program runs in its own process group with default signal handling and only fds 0–2 inherited.
///   The daemon ignores SIGINT / SIGTERM / SIGHUP, and ignored signals carry over into children, so without the
///   reset a timed-out command couldn't be stopped. On timeout the whole group gets SIGTERM, then SIGKILL after
///   1 s, so a script's own children (`sleep`, a pipeline) end with it.
/// Synchronous: call it off the main thread.
enum ProcessRunner {
    static let outputCap = 65_536
    static let truncationMark = "\n…(truncated)"

    static func run(executable: String, arguments: [String], environment: [String: String]?,
                    timeout: TimeInterval = 30) -> ActionResult {
        let captured = capture(executable: executable, arguments: arguments, environment: environment,
                               timeout: timeout, cap: outputCap)
        func text(_ data: Data, _ truncated: Bool) -> String {
            String(decoding: data, as: UTF8.self) + (truncated ? truncationMark : "")
        }
        return ActionResult(exitStatus: captured.exitStatus,
                            stdout: text(captured.stdout, captured.stdoutTruncated),
                            stderr: text(captured.stderr, captured.stderrTruncated),
                            error: captured.error)
    }

    struct Captured {
        var exitStatus: Int32?
        var stdout = Data()
        var stderr = Data()
        var stdoutTruncated = false
        var stderrTruncated = false
        var error: String?
    }

    /// Runs the program and returns its raw output, each stream capped at `cap` bytes. `environment` nil means
    /// the daemon's own.
    static func capture(executable: String, arguments: [String], environment: [String: String]?,
                        timeout: TimeInterval, cap: Int) -> Captured {
        var result = Captured()
        var outPipe: [Int32] = [-1, -1], errPipe: [Int32] = [-1, -1]
        guard pipe(&outPipe) == 0 else { result.error = "couldn't start \(executable): \(errnoText())"; return result }
        guard pipe(&errPipe) == 0 else {
            result.error = "couldn't start \(executable): \(errnoText())"
            outPipe.forEach { close($0) }
            return result
        }
        // Close-on-exec, so programs started elsewhere in the daemon (m1ddc) never hold these pipes open.
        for fd in outPipe + errPipe { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, outPipe[1], 1)
        posix_spawn_file_actions_adddup2(&actions, errPipe[1], 2)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF |
                                                    POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for signal in [SIGINT, SIGTERM, SIGHUP, SIGQUIT, SIGPIPE, SIGCHLD, SIGALRM, SIGUSR1, SIGUSR2] {
            sigaddset(&defaults, signal)
        }
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        var noMask = sigset_t()
        sigemptyset(&noMask)
        posix_spawnattr_setsigmask(&attributes, &noMask)

        let argv: [UnsafeMutablePointer<CChar>?] = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] =
            (environment ?? ProcessInfo.processInfo.environment).map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, executable, &actions, &attributes, argv, envp)
        close(outPipe[1])
        close(errPipe[1])
        guard spawned == 0 else {
            close(outPipe[0])
            close(errPipe[0])
            result.error = "couldn't start \(executable): \(String(cString: strerror(spawned)))"
            return result
        }

        // Drain both pipes as data arrives.
        let readQueue = DispatchQueue(label: "deckcore.process.read")
        let readers = DispatchGroup()
        let out = Sink(cap: cap), err = Sink(cap: cap)
        drain(outPipe[0], into: out, on: readQueue, group: readers)
        drain(errPipe[0], into: err, on: readQueue, group: readers)

        // Timeout: SIGTERM to the whole group, SIGKILL a second later if the program is still there.
        // `exited` is set before the program is reaped, so its pid can't have been reused when we signal it.
        let state = KillState()
        let terminate = DispatchWorkItem {
            state.lock.lock(); defer { state.lock.unlock() }
            guard !state.exited else { return }
            state.timedOut = true
            kill(-pid, SIGTERM)
        }
        let forceKill = DispatchWorkItem {
            state.lock.lock(); defer { state.lock.unlock() }
            guard !state.exited else { return }
            kill(-pid, SIGKILL)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: terminate)
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout + 1, execute: forceKill)

        var info = siginfo_t()
        while waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) == -1, errno == EINTR {}   // exited, not reaped
        state.lock.lock()
        state.exited = true
        let timedOut = state.timedOut
        state.lock.unlock()
        terminate.cancel()
        forceKill.cancel()
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1, errno == EINTR {}

        // A command that leaves something running in the background (`cmd &`) keeps the pipes open. Wait briefly
        // for end-of-file, then take what has arrived; the drains carry on in the background until the pipes close.
        _ = readers.wait(timeout: .now() + (timedOut ? 1.5 : 0.5))
        readQueue.sync {
            result.stdout = out.data
            result.stdoutTruncated = out.truncated
            result.stderr = err.data
            result.stderrTruncated = err.truncated
        }

        let signal = status & 0x7f
        if signal == 0 {
            result.exitStatus = (status >> 8) & 0xff
        }
        if timedOut {
            result.error = "timed out after \(String(format: "%g", timeout)) s"
        } else if signal != 0 {
            result.error = "ended by signal \(signal)"
        }
        return result
    }

    // MARK: - Private

    private final class Sink {
        let cap: Int
        var data = Data()
        var truncated = false
        init(cap: Int) { self.cap = cap }

        func take(_ bytes: UnsafeRawBufferPointer) {
            let room = max(0, cap - data.count)
            if room > 0 { data.append(contentsOf: bytes.prefix(room)) }
            if bytes.count > room { truncated = true }   // beyond the cap: read and dropped, so the program never stalls
        }
    }

    private final class KillState {
        let lock = NSLock()
        var exited = false
        var timedOut = false
    }

    private static func drain(_ fd: Int32, into sink: Sink, on queue: DispatchQueue, group: DispatchGroup) {
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        var buffer = [UInt8](repeating: 0, count: 65_536)
        group.enter()
        source.setEventHandler {
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if count > 0 {
                buffer.withUnsafeBytes { sink.take(UnsafeRawBufferPointer(rebasing: $0.prefix(count))) }
            } else if count == 0 || (errno != EAGAIN && errno != EINTR) {
                source.cancel()                     // end of file, or the pipe broke
            }
        }
        source.setCancelHandler {
            close(fd)
            group.leave()
        }
        source.resume()
    }

    private static func errnoText() -> String { String(cString: strerror(errno)) }
}
