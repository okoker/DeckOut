import Foundation

/// The outcome of one config reload: whether the file loaded, and if not, why (the previous config stays).
public struct ReloadResult: Codable, Equatable {
    public var loaded: Bool
    public var problem: String?

    public init(loaded: Bool, problem: String?) {
        self.loaded = loaded
        self.problem = problem
    }
}

/// Merges bursts of reload requests into one reload. A slider dragged in the config app saves dozens of times a
/// second; each save asks for a reload, and each reload redraws every deck.
///
/// The first request schedules `perform` after `delay`; requests that arrive before it runs ride along, and every
/// one of them gets the same result. A request arriving while `perform` runs (or after) schedules exactly one more.
/// Call `request` on `queue`; `perform` and the completions run there too.
final class ReloadMerger {
    private let delay: TimeInterval
    private let queue: DispatchQueue
    private let perform: () -> ReloadResult
    private var waiting: [(ReloadResult) -> Void] = []
    private var scheduled = false

    init(delay: TimeInterval = 0.15, queue: DispatchQueue = .main, perform: @escaping () -> ReloadResult) {
        self.delay = delay
        self.queue = queue
        self.perform = perform
    }

    func request(_ completion: ((ReloadResult) -> Void)?) {
        if let completion { waiting.append(completion) }
        guard !scheduled else { return }
        scheduled = true
        queue.asyncAfter(deadline: .now() + delay) { [self] in
            let completions = waiting
            waiting = []
            scheduled = false          // from here on, a new request schedules the next reload
            let result = perform()
            completions.forEach { $0(result) }
        }
    }
}
