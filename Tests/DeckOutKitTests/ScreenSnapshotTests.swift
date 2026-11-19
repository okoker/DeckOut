@testable import DeckCore
import SwiftUI
import Testing
@testable import DeckOutKit

// Every screen renders; the PNGs land in the temp folder for a look (light and dark).

@MainActor @Test func writesEveryScreen() throws {   // T-118 (design check)
    let notes = "/System/Applications/Notes.app/Contents/Resources/AppIcon.icns"
    let config = AppConfig(n4: N4Section(
        brightness: 75,
        knobs: ["knob_1": KnobConfig(rotate: KnobAction(action: "display_brightness", step: 5), press: KnobAction(action: "display_brightness_cycle")),
                "knob_4": KnobConfig(rotate: KnobAction(action: "system_volume", step: 2), press: KnobAction(action: "system_mute_toggle"))],
        swipe: nil, lockPhoto: nil,
        presets: [N4Preset(name: "Work", keys: ["key_3": ButtonConfig(action: "app:/System/Applications/Notes.app", icon: notes)],
                           strip: ["1": StripBlockConfig(type: .internet), "4": StripBlockConfig(type: .volume)])],
        activePreset: "Work"))
    let face = DeckFace.of(.n4)
    var images: [String: CGImage] = [:]
    images["key_3"] = DeckPreview.keyImage(path: notes, deck: .n4)
    images["4"] = DeckPreview.upright(jpeg: StripRenderer.volume(percent: 45, muted: false))
    images["1"] = DeckPreview.upright(jpeg: StripRenderer.internet(ms: 12.4, trend: .down, failed: false))
    let captions = config.n4!.knobs.mapValues { ActionNames.knobCaption($0) }

    let size = MainWindow.size
    let screens: [(String, AnyView)] = [
        ("stage", AnyView(VStack(spacing: 0) {
            HStack(spacing: 0) {
                DeckView(face: face, images: images, captions: captions, selection: .constant("key_3"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(StageBackground())
            }
            StatusBar(health: .good, text: "Deck controller running")
        })),
        ("plug-in", AnyView(PlugInScreen())),
        ("pick", AnyView(PickDeckScreen { _ in })),
        ("move", AnyView(MoveToApplicationsScreen(message: AppLocation.problem(bundlePath: "/x/DeckOut.app", identity: .release)!))),
        ("approval", AnyView(NeedsApprovalScreen {})),
        ("problem", AnyView(AgentProblemScreen(message: AppModel.notAnsweringText) {})),
        ("starting", AnyView(StartingScreen())),
    ]
    for (name, view) in screens {
        for dark in [false, true] {
            let png = try Snapshot.png(view, size: size, dark: dark)
            #expect(png.count > 1000)
            try png.write(to: snapshotFolder.appendingPathComponent("screen-\(name)-\(dark ? "dark" : "light").png"))
        }
    }
}
