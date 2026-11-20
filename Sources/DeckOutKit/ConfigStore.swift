import DeckCore
import Foundation

/// The config the window edits. Every change is a whole new config: saved atomically (`ConfigFile.save`), then the
/// agent is asked to reload. Undo puts back the whole config from before the change.
///
/// The file may also be edited by hand while the app is open: before each change the store reads the file again if
/// it changed since the store last read or wrote it, and builds on that. A file that doesn't load is never saved
/// over; `problem` says why until it loads again.
@MainActor
public final class ConfigStore: ObservableObject {
    public let path: String
    @Published public private(set) var config: AppConfig = .empty
    @Published public private(set) var problem: String?
    /// Something the person should know that isn't a problem (a hand edit picked up).
    @Published public private(set) var notice: String?
    @Published public private(set) var undoName: String?
    @Published public private(set) var redoName: String?

    private let reload: () -> Void
    /// The bytes the store last read from or wrote to the file: anything else there is a hand edit.
    private var lastData: Data?
    /// The file on disk doesn't load (broken, or not safe to read): nothing is saved over it, and it is read again
    /// before every change until it loads, so fixing it (even with chmod, which leaves the bytes) is picked up.
    private var loadProblem: String? { didSet { problem = loadProblem ?? saveProblem } }
    /// The last save failed: shown; the next change tries again.
    private var saveProblem: String? { didSet { problem = loadProblem ?? saveProblem } }
    private var undoStack: [(name: String, config: AppConfig)] = []
    private var redoStack: [(name: String, config: AppConfig)] = []
    private static let undoLimit = 200
    private var lastCoalesced: Date?

    public init(path: String, reload: @escaping () -> Void) {
        self.path = path
        self.reload = reload
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Reads the file. Missing: an empty config (the first change creates the file). Unusable: `problem`, and the
    /// last good config stays.
    public func load() {
        let data = FileManager.default.contents(atPath: path)
        switch ConfigFile.load(at: path) {
        case .success(let loaded):
            config = loaded
            loadProblem = nil
            lastData = data
        case .failure(.missing):
            config = .empty
            loadProblem = nil
            lastData = nil
        case .failure(let error):
            loadProblem = error.description
            lastData = data
        }
    }

    /// Re-reads the file if it changed since the store last read or wrote it, or while it doesn't load. A hand
    /// edit that changes the config starts the undo history again: undoing past it would throw it away.
    public func externalChange() {
        guard loadProblem != nil || FileManager.default.contents(atPath: path) != lastData else { return }
        let before = config
        load()
        if loadProblem == nil, config != before {
            undoStack.removeAll()
            redoStack.removeAll()
            updateNames()
            notice = "Picked up a change made outside DeckOut; undo starts again from here"
        }
    }

    /// Applies `edit` to the current config; if anything changed, saves it, asks for a reload, and makes it undoable
    /// under `name` ("Change Action", shown in the Edit menu). `coalescing`: a run of such changes with the same name,
    /// each within a second of the last (a slider dragged), is one undo step.
    public func change(_ name: String, coalescing: Bool = false, _ edit: (inout AppConfig) -> Void) {
        externalChange()
        guard loadProblem == nil else { return }    // the file on disk doesn't load: never save over it
        var next = config
        edit(&next)
        guard next != config else { return }
        let before = config
        guard save(next) else { return }
        let now = Date()
        let continues = coalescing && undoStack.last?.name == name && redoStack.isEmpty
            && lastCoalesced.map { now.timeIntervalSince($0) < 1 } == true
        if !continues {
            undoStack.append((name, before))
            if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        }
        lastCoalesced = coalescing ? now : nil
        redoStack.removeAll()
        updateNames()
    }

    public func undo() {
        externalChange()
        guard loadProblem == nil, let last = undoStack.popLast() else { return }
        let current = config
        guard save(last.config) else {
            undoStack.append(last)
            return
        }
        redoStack.append((last.name, current))
        updateNames()
    }

    public func redo() {
        externalChange()
        guard loadProblem == nil, let next = redoStack.popLast() else { return }
        let current = config
        guard save(next.config) else {
            redoStack.append(next)
            return
        }
        undoStack.append((next.name, current))
        updateNames()
    }

    // MARK: - Private

    /// Writes `newConfig`, then asks the agent to reload. False, with `problem` set, when it couldn't be written.
    private func save(_ newConfig: AppConfig) -> Bool {
        do {
            try ConfigFile.save(newConfig, to: path)
        } catch {
            saveProblem = "Couldn't save the change: \((error as? ConfigFile.SaveError)?.description ?? error.localizedDescription)"
            return false
        }
        config = newConfig
        saveProblem = nil
        notice = nil
        lastData = FileManager.default.contents(atPath: path)
        reload()
        return true
    }

    private func updateNames() {
        undoName = undoStack.last?.name
        redoName = redoStack.last?.name
    }
}
