import Foundation
import Testing
@testable import DeckCore

@Test func cpuPercentFromTickDeltas() {
    let prev = CPUTicks(user: 100, system: 50, idle: 800, nice: 0)
    let cur = CPUTicks(user: 160, system: 70, idle: 920, nice: 0)
    // busy 60 + 20 = 80 of 200 ticks
    #expect(SystemLoad.cpuPercent(prev: prev, cur: cur) == 40)
    // nice counts toward the total, not the busy share (as Stats does)
    let niced = CPUTicks(user: 160, system: 70, idle: 900, nice: 20)
    #expect(SystemLoad.cpuPercent(prev: prev, cur: niced) == 40)
}

@Test func cpuPercentNilWithoutElapsedTicks() {
    let same = CPUTicks(user: 5, system: 5, idle: 5, nice: 5)
    #expect(SystemLoad.cpuPercent(prev: same, cur: same) == nil)
}

@Test func cpuPercentSurvivesCounterWrap() {
    let prev = CPUTicks(user: UInt32.max - 9, system: 0, idle: UInt32.max - 29, nice: 0)
    let cur = CPUTicks(user: 10, system: 0, idle: 50, nice: 0)
    // user advanced 20 across the wrap, idle 80 → 20 %
    #expect(SystemLoad.cpuPercent(prev: prev, cur: cur) == 20)
}

@Test func cpuColourBoundaries() {
    #expect(LoadColour.cpu(49) == .green)
    #expect(LoadColour.cpu(50) == .amber)
    #expect(LoadColour.cpu(79) == .amber)
    #expect(LoadColour.cpu(80) == .red)
}

@Test func memoryColourFollowsPressureLevel() {
    #expect(LoadColour.memory(.normal) == .green)
    #expect(LoadColour.memory(.warning) == .amber)
    #expect(LoadColour.memory(.critical) == .red)
    #expect(PressureLevel(sysctlValue: 1) == .normal)
    #expect(PressureLevel(sysctlValue: 2) == .warning)
    #expect(PressureLevel(sysctlValue: 4) == .critical)
}

@Test func systemReadingsWorkOnThisMac() throws {
    // The sysctl names and host call are right: a typo would silently show "–" on the deck.
    #expect(SystemLoad.readTicks() != nil)
    let mem = try #require(SystemLoad.memoryPercent())
    #expect((0...100).contains(mem))
    #expect(SystemLoad.pressureLevel() != nil)
}

@Test func loadRendersWithMissingFigures() throws {
    for (cpu, mem, level) in [(23, 61, PressureLevel.normal), (nil, 61, .warning), (95, nil, nil), (nil, nil, nil)] as [(Int?, Int?, PressureLevel?)] {
        let img = try decodeImage(StripRenderer.load(cpu: cpu, mem: mem, memLevel: level))
        #expect(img.width == 176 && img.height == 112)
    }
}
