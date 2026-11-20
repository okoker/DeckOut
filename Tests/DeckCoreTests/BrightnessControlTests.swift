import Foundation
import Testing
@testable import DeckCore

/// A stand-in `m1ddc`: lists Left (display 1) and Right (display 2) as the real one does; `display N get luminance`
/// prints what the file `get-N` holds ("fail": "DDC communication failure: no valid reply" and exit 1, as m1ddc does
/// when the monitor gives no valid reply); every call is recorded.
private struct FakeM1ddc {
    let folder: URL
    var path: String { folder.appendingPathComponent("m1ddc").path }

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("deckcore-m1ddc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let script = """
            #!/bin/sh
            dir="$(dirname "$0")"
            echo "$*" >> "$dir/calls.log"
            case "$*" in
              "display list detailed") cat "$dir/list.txt" ;;
              *" get luminance")
                answer="$(cat "$dir/get-$2")"
                if [ "$answer" = "fail" ]; then echo "DDC communication failure: no valid reply"; exit 1; fi
                echo "$answer" ;;
            esac
            """
        try Data(script.utf8).write(to: URL(fileURLWithPath: path))
        #expect(chmod(path, 0o755) == 0)
        let list = """
            [1] LG HDR 4K (4EE3CBE9-3EC1-4366-8EF1-D3E6B04E6B36)
             - Product name:  LG HDR 4K
             - AN Serial:     LEFT1
             - Display ID:    5
            [2] LG HDR 4K (8AB85D9B-1DD6-44DE-98B0-D5F26CB815E2)
             - Product name:  LG HDR 4K
             - AN Serial:     RIGHT2
             - Display ID:    4

            """
        try Data(list.utf8).write(to: folder.appendingPathComponent("list.txt"))
    }

    /// What `display N get luminance` prints from now on.
    func answer(_ display: Int, _ value: String) throws {
        try Data(value.utf8).write(to: folder.appendingPathComponent("get-\(display)"))
    }

    var calls: [String] {
        ((try? String(contentsOf: folder.appendingPathComponent("calls.log"), encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
    }
    var sets: [String] { calls.filter { $0.contains(" set ") } }
    var gets: [String] { calls.filter { $0.hasSuffix(" get luminance") } }
}

/// The messages the control shows, in order; `next()` waits for the next one.
private final class ShownMessages: @unchecked Sendable {
    private let lock = NSLock()
    private var texts: [String] = []
    private let shown = DispatchSemaphore(value: 0)

    func show(_ text: String) {
        lock.lock(); texts.append(text); lock.unlock()
        shown.signal()
    }
    /// The next message shown (nil if none within 5 s).
    func next() -> String? {
        guard shown.wait(timeout: .now() + 5) == .success else { return nil }
        lock.lock(); defer { lock.unlock() }
        return texts.last
    }
}

private let leftAndRight = [DisplayConfig(name: "Left", serial: "LEFT1"), DisplayConfig(name: "Right", serial: "RIGHT2")]

/// Turns the knob by `step` and waits until the turn is applied and its writes have run.
private func turn(_ control: BrightnessControl, _ step: Int, _ messages: ShownMessages) -> String? {
    control.adjust(step: step)
    let message = messages.next()
    control.writeQueue.sync {}
    return message
}

@Test func theFirstTurnReadsTheMonitor() throws {                 // T-170
    // BL-003: a monitor at 100 % that answered 0 at start-up (a reply m1ddc read too early) went to 5 % on the
    // first turn, because the start-up reading was trusted. The first turn reads the monitor itself.
    let fake = try FakeM1ddc()
    try fake.answer(1, "0")
    try fake.answer(2, "0")
    let messages = ShownMessages()
    let control = try #require(BrightnessControl(displays: leftAndRight, m1ddcPath: fake.path, hud: messages.show))
    defer { control.shutdown() }

    try fake.answer(1, "60")
    try fake.answer(2, "60")
    #expect(turn(control, 5, messages) == "☀ 65%  All")
    #expect(fake.sets == ["display 1 set luminance 65", "display 2 set luminance 65"])
}

@Test func aMonitorWithNoReadingIsLeftAlone() throws {            // T-171
    // No valid reading (m1ddc failed, or a number that can't be a brightness): that monitor isn't moved and the
    // message names it; the other monitor still moves. The next turn asks the failed one again.
    let fake = try FakeM1ddc()
    try fake.answer(1, "fail")
    try fake.answer(2, "60")
    let messages = ShownMessages()
    let control = try #require(BrightnessControl(displays: leftAndRight, m1ddcPath: fake.path, hud: messages.show))
    defer { control.shutdown() }

    #expect(turn(control, 5, messages) == "Left: Monitor Error")
    #expect(fake.sets == ["display 2 set luminance 65"])

    try fake.answer(1, "41984")                      // a garbled reply, as a stock m1ddc can print
    #expect(turn(control, 5, messages) == "Left: Monitor Error")
    #expect(fake.sets == ["display 2 set luminance 65", "display 2 set luminance 70"])

    try fake.answer(1, "40")
    #expect(turn(control, 5, messages) == "☀ 45%  All")
    #expect(fake.sets == ["display 2 set luminance 65", "display 2 set luminance 70",
                          "display 1 set luminance 45", "display 2 set luminance 75"])
    // Right, once read, was moved from what the agent knows, not read again.
    #expect(fake.gets.filter { $0.hasPrefix("display 2 ") }.count == 1)
}

@Test func aTurnAfterIdleReadsTheMonitorAgain() throws {           // T-172
    // Within the idle time the agent moves from what it knows; after it, the monitor may have been changed with its
    // own buttons, so the next turn reads it again.
    let fake = try FakeM1ddc()
    try fake.answer(1, "60")
    let messages = ShownMessages()
    let control = try #require(BrightnessControl(displays: [DisplayConfig(name: "Left", serial: "LEFT1")],
                                                 m1ddcPath: fake.path, idleTimeout: 3, hud: messages.show))
    defer { control.shutdown() }

    #expect(turn(control, 5, messages) == "☀ 65%  All")
    try fake.answer(1, "30")                         // changed on the monitor itself
    #expect(turn(control, 5, messages) == "☀ 70%  All")
    Thread.sleep(forTimeInterval: 4.5)               // idle
    #expect(turn(control, 5, messages) == "☀ 35%  All")
    #expect(fake.sets == ["display 1 set luminance 65", "display 1 set luminance 70", "display 1 set luminance 35"])
}

@Test func longMessagesFitTheBox() {                               // T-173
    // The box is 700 pt wide; "Left: Monitor Error" at the usual 80 pt would be cut off.
    let width: CGFloat = 660
    #expect(BrightnessHUD.fontSize(for: "☀ 100%  Right", width: width) == 80)
    let size = BrightnessHUD.fontSize(for: "Left: Monitor Error", width: width)
    #expect(size < 80)
    #expect(BrightnessHUD.textWidth("Left: Monitor Error", fontSize: size) <= width)
}
