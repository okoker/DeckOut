import AppKit
import DeckCore
import Foundation

#if DEBUG
/// Debug builds: `--selftest` drives the app's own editing paths against the running agent, as a person's clicks
/// would, then undoes everything and checks the config file is back as it was, and quits. For test sessions with
/// nobody at the Mac. Harmless on purpose: the only action it runs is `echo`.
@MainActor
enum SelfTest {
    static func runIfAsked(model: AppModel, arguments: [String] = CommandLine.arguments) {
        guard arguments.contains("--selftest") else { return }
        Task { @MainActor in
            let ok = await run(model)
            print("SELFTEST \(ok ? "PASSED" : "FAILED")")
            fflush(stdout)
            exit(ok ? 0 : 1)
        }
    }

    /// A 1200 × 800 picture with stripes, in the temp folder.
    private static func testPhoto() -> String? {
        let w = 1200, h = 800
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        for i in 0..<12 {
            ctx.setFillColor(red: CGFloat(i) / 12, green: 0.4, blue: 1 - CGFloat(i) / 12, alpha: 1)
            ctx.fill(CGRect(x: i * 100, y: 0, width: 100, height: h))
        }
        guard let image = ctx.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return nil }
        let path = NSTemporaryDirectory() + "deckout-selftest-photo.png"
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil ? path : nil
    }

    private static func run(_ model: AppModel) async -> Bool {
        var ok = true
        func check(_ condition: Bool, _ what: String) {
            print("SELFTEST \(condition ? "ok  " : "FAIL") \(what)")
            ok = ok && condition
        }
        func wait(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9)) }

        for _ in 0..<60 where model.link?.state != .connected { await wait(0.5) }
        check(model.link?.state == .connected, "connected to the agent")
        guard let store = model.store, model.link?.state == .connected else { return false }
        let original = FileManager.default.contents(atPath: store.path)
        let deck: DeckKind = model.connectedDecks.contains(.n4) ? .n4 : .n3
        model.show(deck)
        await wait(0.5)
        let key = deck == .n4 ? "key_10" : "lcd_6"

        // A key edit: saved, reloaded by the agent (its status push brings the same config back).
        let command = ActionChoice.runCommand("echo deckout-selftest")
        model.setAction(command, button: key, on: deck)
        check(model.config?.button(deck, key)?.action == command.action, "key set in the app")
        check((try? ConfigFile.load(at: store.path).get().button(deck, key)?.action) == command.action, "key saved to the file")

        // Test runs it in the agent, exactly as a press would.
        let result = await model.test(command)
        check(result?.stdout == "deckout-selftest\n" && result?.exitStatus == 0,
              "Test ran it in the agent: \(result.map { "exit \($0.exitStatus.map(String.init) ?? "–"), \($0.stdout.debugDescription)" } ?? "no answer")")

        // Presets: new (live), switch back, delete it.
        let before = model.livePreset
        let made = model.newPreset()
        check(made != nil && model.livePreset == made, "new preset \(made ?? "?") is live")
        await wait(1)
        check(model.link?.status?.activePresets[deck.rawValue] == made, "the agent shows the new preset")
        model.deleteLivePreset()      // the new one, which is live
        model.makeLive(before)
        check(!model.presetNames.contains(made ?? "-"), "new preset deleted")
        check(model.livePreset == before, "back on \(before)")

        // Brightness: a drag is one undo step.
        let brightness = model.brightness
        for value in stride(from: brightness, through: max(0, brightness - 20), by: -5) { model.setBrightness(value) }
        check(model.brightness == max(0, brightness - 20) || brightness < 5, "brightness dragged")
        store.undo()
        check(model.brightness == brightness, "one undo puts the brightness back")

        // Lock photo (N4): choose a generated picture, preview it on the deck, drag it, Done.
        if model.connectedDecks.contains(.n4) {
            model.show(.n4)
            await wait(0.5)
            let photo = testPhoto()
            check(photo.map { model.choosePhoto($0) } == true, "lock photo chosen and copied")
            model.enterPhotoMode()
            model.setFraming(zoom: 1.5, name: "Zoom Lock Photo")   // a 3:2 picture fills the face's width at zoom 1
            for step in 1...10 {
                model.setFraming(offsetX: Double(step) * 0.02, name: "Move Lock Photo")
                await wait(0.03)
            }
            await wait(0.5)
            check(model.lockPhoto?.offsetX ?? 0 > 0, "photo moved (offset \(model.lockPhoto?.offsetX ?? 0))")
            model.leavePhotoMode()
            check(!model.photoMode, "Done: back to the keys")
            await wait(0.5)
        }

        // Undo everything: the file is back, byte for byte.
        while store.canUndo { store.undo() }
        await wait(1)
        // Compared as configs: the first save writes a hand-written file in the app's own format.
        let restored = try? ConfigFile.load(at: store.path).get()
        check(original.flatMap { try? AppConfig.parse($0) } == restored, "every change undone: the config is as it was")
        check(model.link?.status?.configProblem == nil, "the agent loaded every save")
        return ok
    }
}
#endif
