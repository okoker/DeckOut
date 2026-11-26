import DeckCore
import Foundation

/// Files the deck's controls point at that aren't there (or a script that can't run): the drawing marks those
/// controls and the editor says why. Scripts, files and apps are used where they are, so moving one breaks its key.
public enum MissingFiles {

    public enum ScriptProblem: Equatable { case missing, notExecutable }

    /// Control id → what's wrong, for the deck's live preset and its knobs.
    public static func check(_ config: AppConfig, deck: DeckKind,
                             exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [String: String] {
        var problems: [String: String] = [:]
        func look(_ id: String, action: String?, icon: String?) {
            if let action, let problem = actionProblem(action, exists: exists) {
                problems[id] = problem
            } else if let icon, !exists(icon) {
                problems[id] = "The icon file isn't there any more"
            }
        }
        let buttons = deck == .n4 ? config.n4?.keys ?? [:] : config.n3?.buttons ?? [:]
        for (id, button) in buttons { look(id, action: button.action, icon: button.icon) }
        let knobs = deck == .n4 ? config.n4?.knobs ?? [:] : config.n3?.knobs ?? [:]
        for (id, knob) in knobs {
            guard let list = knob.list else {
                look(id, action: knob.press.action, icon: nil)
                continue
            }
            // A list knob: the first item with a problem, by its number.
            for (index, item) in list.enumerated() {
                let problem = actionProblem(item.action, exists: exists)
                    ?? item.icon.flatMap { exists($0) ? nil : "The icon file isn't there any more" }
                if let problem {
                    problems[id] = "Item \(index + 1): " + problem.prefix(1).lowercased() + problem.dropFirst()
                    break
                }
            }
        }
        if deck == .n4 {
            for (id, block) in config.n4?.strip ?? [:] {
                if let action = block.action, let problem = actionProblem(action, exists: exists) {
                    problems[id] = problem
                } else if block.type == .picture, let icon = block.icon, !exists(icon) {
                    problems[id] = "The picture isn't there any more"
                }
            }
        }
        return problems
    }

    private static func actionProblem(_ action: String, exists: (String) -> Bool) -> String? {
        switch ActionChoice(action: action, step: nil) {
        case .openApp(let path) where !path.isEmpty && !exists(path): return "The app isn't there any more"
        case .openFile(let path) where !path.isEmpty && !exists(path): return "The file or folder isn't there any more"
        case .runScript(let path) where !path.isEmpty:
            switch scriptProblem(path) {
            case .missing?: return "The script isn't there any more"
            case .notExecutable?: return "The script isn't executable"
            case nil: return nil
            }
        default: return nil
        }
    }

    public static func scriptProblem(_ path: String) -> ScriptProblem? {
        guard FileManager.default.fileExists(atPath: path) else { return .missing }
        return FileManager.default.isExecutableFile(atPath: path) ? nil : .notExecutable
    }

    /// Adds the owner's execute bit (`chmod u+x`), when the person asks; nil when done, else why not, in words.
    public static func makeExecutable(_ path: String) -> String? {
        var st = stat()
        guard stat(path, &st) == 0 else { return whyNotExecutable(errno) }
        return chmod(path, (st.st_mode & 0o7777) | S_IXUSR) == 0 ? nil : whyNotExecutable(errno)
    }

    /// Why a script couldn't be made executable, from the error the system gave.
    public static func whyNotExecutable(_ code: Int32) -> String {
        switch code {
        case EPERM: return "Only the script's owner can make it executable."
        case EROFS: return "The script is on a disk that can't be changed."
        case EACCES: return "DeckOut can't get into the script's folder."
        case ENOENT: return "The script isn't there any more."
        default: return "It couldn't be made executable (\(String(cString: strerror(code))))."
        }
    }

    /// A note when the file sits where macOS asks before a background program reads it.
    public static func guardedFolderNote(_ path: String, home: String) -> String? {
        let guarded = ["/Desktop/", "/Documents/", "/Downloads/", "/Library/Mobile Documents/"].map { home + $0 }
        guard guarded.contains(where: path.hasPrefix) else { return nil }
        return "It's in a folder macOS guards: the first time it runs, macOS asks whether DeckOut may use that folder."
    }
}
