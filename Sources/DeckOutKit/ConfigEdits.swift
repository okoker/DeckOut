import DeckCore

/// Reading and changing one control in the config: keys, buttons and strip blocks in the live preset, knobs on the
/// deck. A deck with no section yet gets one on its first edit: one preset, "Default", brightness 75.
extension AppConfig {

    public func button(_ deck: DeckKind, _ id: String) -> ButtonConfig? {
        deck == .n4 ? n4?.keys[id] : n3?.buttons[id]
    }

    public mutating func setButton(_ deck: DeckKind, _ id: String, _ value: ButtonConfig?) {
        switch deck {
        case .n4:
            var section = n4 ?? Self.newN4
            section.presets[section.liveIndex].keys[id] = value
            n4 = section
        case .n3:
            var section = n3 ?? Self.newN3
            section.presets[section.liveIndex].buttons[id] = value
            n3 = section
        }
    }

    public func knob(_ deck: DeckKind, _ id: String) -> KnobConfig? {
        deck == .n4 ? n4?.knobs[id] : n3?.knobs[id]
    }

    public mutating func setKnob(_ deck: DeckKind, _ id: String, _ value: KnobConfig?) {
        switch deck {
        case .n4:
            var section = n4 ?? Self.newN4
            section.knobs[id] = value
            n4 = section
        case .n3:
            var section = n3 ?? Self.newN3
            section.knobs[id] = value
            n3 = section
        }
    }

    public func stripBlock(_ id: String) -> StripBlockConfig? { n4?.strip[id] }

    public mutating func setStripBlock(_ id: String, _ value: StripBlockConfig?) {
        var section = n4 ?? Self.newN4
        section.presets[section.liveIndex].strip[id] = value
        n4 = section
    }

    static let newN4 = N4Section(brightness: 75, knobs: [:], swipe: nil, lockPhoto: nil,
                                 presets: [N4Preset(name: "Default", keys: [:], strip: [:])], activePreset: "Default")
    static let newN3 = N3Section(brightness: 75, knobs: [:], presets: [N3Preset(name: "Default", buttons: [:])],
                                 activePreset: "Default")
}

extension N4Section {
    /// The live preset's index: the one named `activePreset`, else the first (as the agent picks it).
    var liveIndex: Int { presets.firstIndex { $0.name == activePreset } ?? 0 }
}

extension N3Section {
    var liveIndex: Int { presets.firstIndex { $0.name == activePreset } ?? 0 }
}
