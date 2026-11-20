import DeckCore
import SwiftUI
import Testing
@testable import DeckOutKit

@Test func monitorChoicesEditDisplays() {   // T-150
    var config = AppConfig.empty
    // Use two monitors: named, in the order the switch key cycles them.
    config.useMonitor(serial: "AAA", name: "Left", true)
    config.useMonitor(serial: "BBB", name: "Right", true)
    #expect(config.displays == [DisplayConfig(name: "Left", serial: "AAA"), DisplayConfig(name: "Right", serial: "BBB")])
    // Renaming keeps the place in the order; an empty name falls back to what it was.
    config.renameMonitor(serial: "AAA", to: "Desk")
    config.renameMonitor(serial: "BBB", to: "  ")
    #expect(config.displays?.map(\.name) == ["Desk", "Right"])
    // Reorder.
    config.moveMonitor(serial: "BBB", up: true)
    #expect(config.displays?.map(\.serial) == ["BBB", "AAA"])
    config.moveMonitor(serial: "BBB", up: true)            // already first: nothing
    #expect(config.displays?.map(\.serial) == ["BBB", "AAA"])
    // Using one twice doesn't duplicate it; not using it takes it out; none left → no `displays` at all.
    config.useMonitor(serial: "AAA", name: "Again", true)
    #expect(config.displays?.count == 2)
    config.useMonitor(serial: "AAA", name: "", false)
    config.useMonitor(serial: "BBB", name: "", false)
    #expect(config.displays == nil)
}

@MainActor @Test func settingsDraw() throws {   // T-150 (design check)
    var config = AppConfig.empty
    config.useMonitor(serial: "AAA111TEST", name: "Left", true)
    let model = try previewModel(config, deck: .n4, selection: nil)
    model.monitors = MonitorList.parse(detailedFixture)
    model.monitorPlaces = [5: "Left", 4: "Right"]
    for (name, view) in [("general", AnyView(GeneralSettings(model: model))),
                         ("monitors", AnyView(MonitorSettings(model: model))),
                         ("about", AnyView(AboutSettings(model: model)))] {
        try Snapshot.windowPNG(view, size: CGSize(width: 520, height: 360), dark: false)
            .write(to: snapshotFolder.appendingPathComponent("settings-\(name).png"))
    }
}
