import DeckCore

/// Reading and changing one control in the config: keys, buttons, knobs and strip blocks, all in the live preset. A
/// deck with no section yet gets one on its first edit: one preset, "Default" (on the N4 the baseline, `baselineN4`),
/// brightness 75. A section already in the file is never replaced.
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
            section.presets[section.liveIndex].knobs[id] = value
            n4 = section
        case .n3:
            var section = n3 ?? Self.newN3
            section.presets[section.liveIndex].knobs[id] = value
            n3 = section
        }
    }

    public func stripBlock(_ id: String) -> StripBlockConfig? { n4?.strip[id] }

    public mutating func setStripBlock(_ id: String, _ value: StripBlockConfig?) {
        var section = n4 ?? Self.newN4
        section.presets[section.liveIndex].strip[id] = value
        n4 = section
    }

    static let newN4 = N4Section(brightness: 75, swipe: .nextPreset, lockPhoto: nil,
                                 presets: [baselineN4("Default")], activePreset: "Default")

    /// What a new N4 preset starts with, whatever the live preset holds, and an N4's first preset (owner,
    /// 26/11/2026): knob 2 monitor brightness (press: switch monitor), knob 4 volume (press: mute), block 1 latency
    /// (no tap), block 2 CPU / memory (tap: Activity Monitor); knobs 1 and 3, blocks 3–4 and the keys empty. Nothing
    /// personal (no ZR7, no scripts): a person's own setup lives in their file.
    static func baselineN4(_ name: String) -> N4Preset {
        N4Preset(name: name, keys: [:],
                 strip: ["1": StripBlockConfig(type: .internet),
                         "2": StripBlockConfig(type: .load,
                                               action: "app:/System/Applications/Utilities/Activity Monitor.app")],
                 knobs: ["knob_2": KnobConfig(rotate: KnobAction(action: "display_brightness", step: 5),
                                              press: KnobAction(action: "display_brightness_cycle")),
                         "knob_4": KnobConfig(rotate: KnobAction(action: "system_volume", step: 5),
                                              press: KnobAction(action: "system_mute_toggle"))])
    }
    static let newN3 = N3Section(brightness: 75, presets: [N3Preset(name: "Default", buttons: [:])],
                                 activePreset: "Default")
}

extension N4Section {
    /// The live preset's index: the one named `activePreset`, else the first (as the agent picks it).
    var liveIndex: Int { presets.firstIndex { $0.name == activePreset } ?? 0 }
}

extension N3Section {
    var liveIndex: Int { presets.firstIndex { $0.name == activePreset } ?? 0 }
}

// MARK: - Presets and brightness

extension AppConfig {

    public func presetNames(_ deck: DeckKind) -> [String] {
        deck == .n4 ? n4?.presets.map(\.name) ?? [] : n3?.presets.map(\.name) ?? []
    }

    /// The live preset's name (as the agent picks it: the named one, else the first).
    public func livePreset(_ deck: DeckKind) -> String? {
        deck == .n4 ? n4?.active.name : n3?.active.name
    }

    public mutating func makeLive(_ name: String, deck: DeckKind) {
        guard presetNames(deck).contains(name) else { return }
        edit(deck) { $0.activePreset = name } n3: { $0.activePreset = name }
    }

    /// The name New Preset offers: "Preset N", N one more than the presets there are (or the next free).
    public func suggestedPresetName(_ deck: DeckKind) -> String {
        var config = self
        config.ensureDeck(deck)                 // a deck with no section yet has its Default
        let names = config.presetNames(deck)
        return freeName(in: names, from: names.count + 1) { "Preset \($0)" }
    }

    /// A new layout under `name` (trimmed), made live: on the N4 the baseline (`baselineN4`), on the N3 blank but for
    /// the live preset's knobs' built-in halves (volume, mute, monitor brightness, switch monitor) (owner,
    /// 26/11/2026). False, and nothing changed, for an empty or taken name.
    @discardableResult
    public mutating func addPreset(_ name: String, deck: DeckKind) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var config = self
        config.ensureDeck(deck)
        guard !trimmed.isEmpty, !config.presetNames(deck).contains(trimmed) else { return false }
        config.edit(deck) {
            $0.presets.append(Self.baselineN4(trimmed))
            $0.activePreset = trimmed
        } n3: {
            $0.presets.append(N3Preset(name: trimmed, buttons: [:],
                                       knobs: $0.active.knobs.compactMapValues { $0.builtInsOnly() }))
            $0.activePreset = trimmed
        }
        self = config
        return true
    }

    /// A copy of `name`'s layout called "<name> copy" (then "copy 2", …), made live. Returns its name.
    @discardableResult
    public mutating func duplicatePreset(_ name: String, deck: DeckKind) -> String? {
        guard presetNames(deck).contains(name) else { return nil }
        let copy = freeName(in: presetNames(deck), from: 1) { $0 == 1 ? "\(name) copy" : "\(name) copy \($0)" }
        edit(deck) { section in
            var preset = section.presets.first { $0.name == name }!
            preset.name = copy
            section.presets.append(preset)
            section.activePreset = copy
        } n3: { section in
            var preset = section.presets.first { $0.name == name }!
            preset.name = copy
            section.presets.append(preset)
            section.activePreset = copy
        }
        return copy
    }

    /// Renames, keeping it live if it was. False (nothing changed) for an empty name or one already taken.
    @discardableResult
    public mutating func renamePreset(_ name: String, to newName: String, deck: DeckKind) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let names = presetNames(deck)
        guard names.contains(name), !trimmed.isEmpty, trimmed == name || !names.contains(trimmed) else { return false }
        edit(deck) { section in
            let index = section.presets.firstIndex { $0.name == name }!
            section.presets[index].name = trimmed
            if section.activePreset == name { section.activePreset = trimmed }
        } n3: { section in
            let index = section.presets.firstIndex { $0.name == name }!
            section.presets[index].name = trimmed
            if section.activePreset == name { section.activePreset = trimmed }
        }
        return true
    }

    /// Deletes a preset, never the last one; deleting the live one makes the first left live.
    @discardableResult
    public mutating func deletePreset(_ name: String, deck: DeckKind) -> Bool {
        let names = presetNames(deck)
        guard names.count > 1, names.contains(name) else { return false }
        let wasLive = livePreset(deck) == name
        edit(deck) { section in
            section.presets.removeAll { $0.name == name }
            if wasLive { section.activePreset = section.presets[0].name }
        } n3: { section in
            section.presets.removeAll { $0.name == name }
            if wasLive { section.activePreset = section.presets[0].name }
        }
        return true
    }

    public func brightness(_ deck: DeckKind) -> Int {
        (deck == .n4 ? n4?.brightness : n3?.brightness) ?? 75
    }

    public mutating func setBrightness(_ deck: DeckKind, _ value: Int) {
        ensureDeck(deck)
        let clamped = min(100, max(0, value))
        edit(deck) { $0.brightness = clamped } n3: { $0.brightness = clamped }
    }

    // MARK: - Private

    /// Gives the deck a section ("Default", brightness 75) if it has none yet.
    public mutating func ensureDeck(_ deck: DeckKind) {
        if deck == .n4, n4 == nil { n4 = Self.newN4 }
        if deck == .n3, n3 == nil { n3 = Self.newN3 }
    }

    private mutating func edit(_ deck: DeckKind, n4 editN4: (inout N4Section) -> Void, n3 editN3: (inout N3Section) -> Void) {
        switch deck {
        case .n4: if var section = n4 { editN4(&section); n4 = section }
        case .n3: if var section = n3 { editN3(&section); n3 = section }
        }
    }

    private func freeName(in names: [String], from start: Int, _ make: (Int) -> String) -> String {
        var n = start
        while names.contains(make(n)) { n += 1 }
        return make(n)
    }
}

// MARK: - Monitors

extension AppConfig {
    /// Adds the monitor to `displays` (at the end of the cycle order) or takes it out; none left → no `displays`.
    public mutating func useMonitor(serial: String, name: String, _ use: Bool) {
        var list = displays ?? []
        if use {
            guard !list.contains(where: { $0.serial == serial }) else { return }
            list.append(DisplayConfig(name: name.isEmpty ? serial : name, serial: serial))
        } else {
            list.removeAll { $0.serial == serial }
        }
        displays = list.isEmpty ? nil : list
    }

    /// Renames a monitor in place; an empty name changes nothing.
    public mutating func renameMonitor(serial: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var list = displays, let index = list.firstIndex(where: { $0.serial == serial }) else { return }
        list[index] = DisplayConfig(name: trimmed, serial: serial)
        displays = list
    }

    /// Moves a monitor one place earlier (up) or later in the cycle order.
    public mutating func moveMonitor(serial: String, up: Bool) {
        guard var list = displays, let index = list.firstIndex(where: { $0.serial == serial }) else { return }
        let target = up ? index - 1 : index + 1
        guard list.indices.contains(target) else { return }
        list.swapAt(index, target)
        displays = list
    }
}
