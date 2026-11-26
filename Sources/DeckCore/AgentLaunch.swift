import Foundation

/// How the agent starts: which config file it reads and where its log goes.
public enum AgentLaunch {

    /// `--config <path>` first (development); inside DeckOut the identity's file, whether or not it exists yet
    /// (the app writes it there); otherwise, for a hand install, today's candidates. Nil only for `--config`
    /// without a value.
    public static func configPath(arguments: [String], identity: AppIdentity?, home: String, execDir: String,
                                  exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String? {
        if arguments.contains("--config") || identity == nil {
            return ConfigFile.resolvePath(arguments: arguments, home: home, execDir: execDir, exists: exists)
        }
        return identity!.configPath(home: home)
    }

    /// The distributed notification `DeckOutAgent --post-reload` sends and the agent listens for (the app asks
    /// over XPC instead, `AgentXPC.reload`): one per DeckOut, its agent label + `.reload`, so a reload for DeckOut
    /// Dev never reloads DeckOut; a hand install has its own. 1.0, as StreamDeckController, used
    /// `com.streamdeck.controller.reload`.
    public static func reloadNotification(identity: AppIdentity?) -> String {
        (identity?.agentLabel ?? AppIdentity.release.bundleID) + ".reload"
    }

    /// Moves the log to `<path>.1` (replacing an older one) when it is over `limit` bytes, so one run's log
    /// never grows without end across restarts. Called once, at start.
    public static func rollLog(at path: String, limit: Int = 5_000_000) {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int,
              size > limit else { return }
        let old = path + ".1"
        try? FileManager.default.removeItem(atPath: old)
        try? FileManager.default.moveItem(atPath: path, toPath: old)
    }

    /// Sends stdout and stderr to `path`, appending: the folder is made 0700, the file 0600. launchd gives an
    /// agent registered from an app bundle no log file of its own (its plist can't name a per-user path).
    public static func redirectOutput(to path: String) throws {
        let folder = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        fflush(stdout)
        fflush(stderr)
        dup2(fd, STDOUT_FILENO)
        dup2(fd, STDERR_FILENO)
        close(fd)
    }
}
