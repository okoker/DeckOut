import AppKit
import DeckCore
import SwiftUI

/// The standard Settings window (⌘,): General, Monitors, About.
public struct SettingsView: View {
    @ObservedObject var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        TabView {
            GeneralSettings(model: model).tabItem { Label("General", systemImage: "gearshape") }
            MonitorSettings(model: model).tabItem { Label("Monitors", systemImage: "display.2") }
            AboutSettings(model: model).tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 400)
    }
}

struct GeneralSettings: View {
    @ObservedObject var model: AppModel
    @State private var confirmingRemove = false

    var body: some View {
        Form {
            Section("Deck controller") {
                LabeledContent("State") {
                    HStack(spacing: 6) {
                        Circle().fill(color(model.statusLine.health)).frame(width: 7, height: 7)
                        Text(model.statusLine.text).lineLimit(2)
                    }
                }
                if let status = model.link?.status {
                    LabeledContent("Version", value: "\(status.version) (\(status.build ?? "older build"))")
                    LabeledContent("Your shell's settings") {
                        HStack {
                            Text(status.environment.state == .resolved ? "Read"
                                 : "Not read (\(status.environment.detail ?? "unknown")); using a standard PATH")
                            Spacer()
                            Button("Read Again") { model.refreshEnvironment() }
                        }
                    }
                    LabeledContent("Accessibility") {
                        HStack {
                            Text(status.accessibility == true ? "Allowed: shortcuts and media keys work"
                                 : "Not allowed: shortcuts and media keys do nothing")
                            Spacer()
                            if status.accessibility != true { Button("Allow…") { model.requestAccessibility() } }
                        }
                    }
                }
            }
            Section {
                if let problem = model.removalProblem {
                    Text(problem).foregroundStyle(.red)
                }
                LabeledContent("Login Items") {
                    HStack {
                        Text("Starts at login and runs in the background.")
                        Spacer()
                        Button("Stop and Remove…") { confirmingRemove = true }.disabled(model.removed)
                    }
                }
            } footer: {
                Text("To remove DeckOut: Stop and Remove, then drag DeckOut to the Bin. Your settings stay in \(model.configFolderForPeople).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Stop the deck controller and take it out of Login Items?", isPresented: $confirmingRemove) {
            Button("Stop and Remove", role: .destructive) { Task { await model.stopAndRemove() } }
        } message: {
            Text("Your decks stop until you start it again from DeckOut.")
        }
    }

    private func color(_ health: AppModel.Health) -> Color {
        health == .good ? Color(rgb: 0x30D158) : health == .busy ? Color(rgb: 0xFF9F0A) : Color(rgb: 0xFF453A)
    }
}

/// Which monitors the brightness keys and knobs set, their names, and the order Switch Monitor goes through them.
struct MonitorSettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                ForEach(model.monitorsInOrder) { monitor in
                    let used = model.displayConfig(monitor.serial)
                    let silent = monitor.answers == false
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(get: { used != nil }, set: { model.useMonitor(monitor, $0) }))
                            .labelsHidden()
                            .disabled(silent && used == nil)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.monitorLabel(monitor))
                            Text(silent ? "Doesn't answer brightness control" : "Serial \(monitor.serial)")
                                .font(.caption).foregroundStyle(silent ? Color(rgb: 0xFF9F0A) : .secondary)
                        }
                        Spacer()
                        if let used {
                            CommitTextField(value: used.name, placeholder: "Name") { model.renameMonitor(monitor.serial, to: $0) }
                                .labelsHidden()
                                .frame(width: 110)
                            Button { model.moveMonitor(monitor.serial, up: true) } label: { Image(systemName: "chevron.up") }
                                .buttonStyle(.borderless).help("Earlier in the Switch Monitor order")
                            Button { model.moveMonitor(monitor.serial, up: false) } label: { Image(systemName: "chevron.down") }
                                .buttonStyle(.borderless).help("Later in the Switch Monitor order")
                        }
                    }
                }
                ForEach((model.config?.displays ?? []).filter { d in !model.monitors.contains { $0.serial == d.serial } },
                        id: \.serial) { display in
                    HStack {
                        Text(display.name)
                        Text("not connected").foregroundStyle(.secondary)
                        Spacer()
                        Button("Forget") { model.store?.change("Stop Using Monitor") { $0.useMonitor(serial: display.serial, name: "", false) } }
                    }
                }
                if let note = model.monitorsNote { Text(note).foregroundStyle(.secondary) }
            } header: {
                HStack {
                    Text("Monitors for the brightness keys and knobs")
                    Spacer()
                    Button("Look Again") { model.loadMonitors() }.controlSize(.small)
                }
            } footer: {
                Text("Switch Monitor goes through the ones turned on, in this order.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { model.loadMonitors() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            model.loadMonitors()
        }
    }
}

struct AboutSettings: View {
    @ObservedObject var model: AppModel

    /// The licences keep their 78-character lines, so the font is small enough for the longest to fit the tab:
    /// 520 pt less 20 pt padding each side and 16 pt for a scroll bar.
    static let licenceFontSize: CGFloat = 9.5
    static let licenceWidth: CGFloat = 520 - 2 * 20 - 16

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.identity?.appName ?? "DeckOut").font(.title2.weight(.semibold))
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–") (\(model.appBuild))")
                            .foregroundStyle(.secondary)
                        Text("© Koker · MIT licence · github.com/okoker/DeckOut").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                ForEach([("DeckOut", "DeckOut-LICENSE.txt"), ("Phosphor Icons 2.1.2", "Phosphor-LICENSE.txt"),
                         ("m1ddc 1.3.3", "m1ddc-LICENSE.txt")], id: \.0) { name, file in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name).font(.headline)
                        Text(licence(file)).font(.system(size: Self.licenceFontSize, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func licence(_ file: String) -> String {
        Bundle.main.url(forResource: file, withExtension: nil).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            ?? "(MIT licence; the text ships in the app's Resources.)"
    }
}
