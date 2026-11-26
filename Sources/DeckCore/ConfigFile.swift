import Foundation

/// The config file on disk: where it is, whether it is safe to read, reading it, and writing it.
///
/// Reads refuse a file that is a symlink, owned by someone else, or writable by group or others: anyone who can
/// change it can make the decks run commands as you. Writes are atomic (a temp file in the same folder, then
/// `rename`), at mode 0600, and the first save keeps the file as it was in `<path>.before-app`, because the
/// v1.0.0 daemon can't read the preset format and rolling back needs the old file; likewise `<path>.before-2.2` for
/// 2.1.0, which can't read knobs in presets.
public enum ConfigFile {

    /// The copy the first save by 2.2 keeps of the file as it was (`<path>.before-2.2`): 2.1.0 can't read knobs in
    /// presets, so going back to it is a restore of this copy (docs/design/knob_lists.md).
    public static let rollbackSuffix = ".before-2.2"

    public enum LoadError: Error, Equatable, CustomStringConvertible {
        case missing(path: String)
        case insecure(String)
        case invalid(String)

        public var description: String {
            switch self {
            case .missing(let path): return "No config yet at \(path)"
            case .insecure(let reason): return "Config refused: \(reason)"
            case .invalid(let reason): return "Config doesn't load: \(reason)"
            }
        }
    }

    /// Why a config wasn't written.
    public enum SaveError: Error, Equatable, CustomStringConvertible {
        /// What would be written doesn't load back (the agent would refuse it): the file is left as it was.
        case wouldNotLoad(String)

        public var description: String {
            switch self {
            case .wouldNotLoad(let reason): return "Not saved: the result wouldn't load (\(reason))"
            }
        }
    }

    /// Where to look, in order, when `--config` isn't given.
    public static func candidates(home: String, execDir: String) -> [String] {
        [AppIdentity.release.configPath(home: home), execDir + "/config.json"]
    }

    /// `--config <path>`, else the first candidate that exists, else the first candidate (where the app will
    /// write it). Nil only for `--config` without a value.
    public static func resolvePath(arguments: [String], home: String, execDir: String,
                                   exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String? {
        if let flag = arguments.firstIndex(of: "--config") {
            return flag + 1 < arguments.count ? arguments[flag + 1] : nil
        }
        let paths = candidates(home: home, execDir: execDir)
        return paths.first(where: exists) ?? paths[0]
    }

    /// Why the file at `path` must not be read, or nil when it is safe. `lstat`, so a symlink is seen as one.
    public static func securityProblem(at path: String) -> String? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return "cannot read \(path): \(String(cString: strerror(errno)))" }
        switch st.st_mode & S_IFMT {
        case S_IFLNK: return "\(path) is a symlink; use a regular file"
        case S_IFREG: break
        default: return "\(path) is not a regular file"
        }
        if st.st_uid != getuid() {
            return "\(path) is owned by uid \(st.st_uid), not by you (uid \(getuid()))"
        }
        let posix = st.st_mode & 0o777
        if posix & 0o022 != 0 {
            return "\(path) is writable by other users (mode \(String(posix, radix: 8))); run chmod 600 \(path)"
        }
        return nil
    }

    public static func load(at path: String) -> Result<AppConfig, LoadError> {
        var st = stat()
        if lstat(path, &st) != 0, errno == ENOENT { return .failure(.missing(path: path)) }
        if let problem = securityProblem(at: path) { return .failure(.insecure(problem)) }
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            return .failure(.invalid("cannot read \(path): \(error.localizedDescription)"))
        }
        do {
            return .success(try AppConfig.parse(data))
        } catch {
            return .failure(.invalid(describe(error)))
        }
    }

    /// The config to start with. Without a usable file the daemon still starts, with no decks set up (they stay
    /// blank), and reports why; a later reload that loads replaces it. Under launchd's KeepAlive, exiting instead
    /// would restart it straight into the same failure, forever.
    public static func startupConfig(at path: String) -> (config: AppConfig, problem: String?) {
        switch load(at: path) {
        case .success(let config): return (config, nil)
        case .failure(let error): return (.empty, error.description)
        }
    }

    /// Writes `config` to `path` atomically at mode 0600, creating the folder (0700) if needed. Before the first
    /// save over an existing file, copies that file to `<path>.before-app`, and before the first save by 2.2 to
    /// `<path>.before-2.2` (each once; later saves leave them alone).
    /// Throws `SaveError.wouldNotLoad`, writing nothing, when the encoded config wouldn't load back.
    public static func save(_ config: AppConfig, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let folder = url.deletingLastPathComponent().path
        if !FileManager.default.fileExists(atPath: folder) {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
        let data = try config.encoded()
        // Only write what loads back and re-encodes to the same bytes: the agent reads it as written.
        do {
            guard try AppConfig.parse(data).encoded() == data else { throw SaveError.wouldNotLoad("it reads back differently") }
        } catch let error as SaveError {
            throw error
        } catch {
            throw SaveError.wouldNotLoad(describe(error))
        }

        // Each copy once, of the file as it was before the first save that needed it.
        var st = stat()
        for backup in [path + ".before-app", path + rollbackSuffix] where lstat(path, &st) == 0 && lstat(backup, &st) != 0 {
            try writeNewFile(try Data(contentsOf: url), to: backup)
        }

        let temp = folder + "/.\(url.lastPathComponent).\(UUID().uuidString).tmp"
        try writeNewFile(data, to: temp)
        guard rename(temp, path) == 0 else {
            let error = posixError()
            unlink(temp)
            throw error
        }
    }

    // MARK: - Private

    /// Creates `path` (which must not exist) at mode 0600 and writes `data` to disk.
    private static func writeNewFile(_ data: Data, to path: String) throws {
        let fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw posixError() }
        var failure: Error?
        if fchmod(fd, 0o600) != 0 { failure = posixError() }
        data.withUnsafeBytes { buffer in
            var offset = 0
            while failure == nil, offset < buffer.count {
                let written = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if written <= 0 { failure = posixError() } else { offset += written }
            }
        }
        if failure == nil, fsync(fd) != 0 { failure = posixError() }
        close(fd)
        if let failure {
            unlink(path)
            throw failure
        }
    }

    private static func posixError() -> Error {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    /// A decoding error as a person can read it: what is wrong, and where in the file.
    static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return error.localizedDescription }
        func place(_ context: DecodingError.Context) -> String {
            var path = ""
            for key in context.codingPath {
                if let index = key.intValue { path += "[\(index)]" } else { path += (path.isEmpty ? "" : ".") + key.stringValue }
            }
            return path.isEmpty ? "" : " (at \(path))"
        }
        func detail(_ context: DecodingError.Context) -> String {
            let underlying = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
            return context.debugDescription + (underlying.map { " \($0)" } ?? "") + place(context)
        }
        switch decoding {
        case .keyNotFound(let key, let context): return "\"\(key.stringValue)\" is missing" + place(context)
        case .dataCorrupted(let context): return detail(context)
        case .typeMismatch(_, let context), .valueNotFound(_, let context): return detail(context)
        @unknown default: return "\(error)"
        }
    }
}
