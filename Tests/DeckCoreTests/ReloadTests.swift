import Foundation
import Testing
@testable import DeckCore

// MARK: - Reload merging (BL-001)

@Test func burstOfRequestsReloadsOnce() async {            // T-061
    var performed = 0
    nonisolated(unsafe) let merger = ReloadMerger(delay: 0.05, queue: .main) { performed += 1; return ReloadResult(loaded: true, problem: nil) }
    let results = await withCheckedContinuation { (done: CheckedContinuation<[ReloadResult], Never>) in
        DispatchQueue.main.async {
            var got: [ReloadResult] = []
            for _ in 0..<20 { merger.request { got.append($0); if got.count == 20 { done.resume(returning: got) } } }
        }
    }
    #expect(performed == 1)
    #expect(results.allSatisfy { $0.loaded })
}

@Test func brightnessIsRebuiltOnlyWhenDisplaysChange() {   // T-062
    let a = DisplayConfig(name: "Left", serial: "S1"), b = DisplayConfig(name: "Right", serial: "S2")
    #expect(!Daemon.displaysChanged([a, b], [a, b]))
    #expect(Daemon.displaysChanged([a, b], [b, a]))
    #expect(Daemon.displaysChanged(nil, [a]))
    #expect(!Daemon.displaysChanged(nil, []))
}

@Test func outsideReloadRebuildsTheMonitorControl() async {         // T-093
    // A monitor plugged in after start is found again on a reload from outside (`--post-reload`), as in v1.0.0;
    // the app's own saves keep reusing the control. No displays here, so m1ddc never runs.
    nonisolated(unsafe) let daemon = Daemon(config: .empty, environment: ShellEnvironment(fixed: [:]))
    let builds: [Int] = await withCheckedContinuation { done in
        DispatchQueue.main.async {
            let before = daemon.brightnessGeneration
            daemon.reload(.empty)
            let afterSave = daemon.brightnessGeneration
            daemon.reload(.empty, rebuildMonitors: true)
            done.resume(returning: [before, afterSave, daemon.brightnessGeneration])
        }
    }
    #expect(builds[1] == builds[0])
    #expect(builds[2] == builds[0] + 1)
}
