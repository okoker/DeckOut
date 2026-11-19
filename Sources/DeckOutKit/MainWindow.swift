import DeckCore
import ServiceManagement
import SwiftUI

/// The main window (mockup A, `docs/assets/config_app_main_window.html`): deck buttons in the toolbar, the deck on
/// its stage with the inspector beside it, and a status line.
public struct MainWindow: View {
    @ObservedObject var model: AppModel

    public static let size = CGSize(width: 946, height: 488)   // below the toolbar: 946 × 544 with it

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            content
            StatusBar(health: model.statusLine.health, text: model.statusLine.text)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                ForEach([DeckKind.n4, .n3], id: \.self) { deck in
                    DeckButton(deck: deck, plugged: model.connectedDecks.contains(deck), shown: model.shown == deck) {
                        model.show(deck)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.recheckRegistration() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.screen {
        case .moveToApplications(let message): MoveToApplicationsScreen(message: message)
        case .starting: StartingScreen()
        case .needsApproval: NeedsApprovalScreen { SMAppService.openSystemSettingsLoginItems() }
        case .agentProblem(let message): AgentProblemScreen(message: message) { Task { await model.tryAgain() } }
        case .plugIn: PlugInScreen()
        case .pickDeck: PickDeckScreen { model.show($0) }
        case .deck(let deck):
            DeckStage(face: DeckFace.of(deck), images: model.images, captions: model.captions,
                      selection: $model.selection, config: model.config)
        }
    }
}

/// The deck on its stage, and the inspector for the selected control.
struct DeckStage: View {
    let face: DeckFace
    let images: [String: CGImage]
    let captions: [String: String]
    @Binding var selection: String?
    let config: AppConfig?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 14) {
                DeckView(face: face, images: images, captions: captions, selection: $selection)
                Text("Click a key, strip block or knob to set it up")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(StageBackground())
            .contentShape(Rectangle())
            .onTapGesture { selection = nil }
            Divider()
            Inspector(face: face, selection: selection, config: config)
                .frame(width: 300)
        }
    }
}

/// What the selected control does (read-only until editing arrives).
struct Inspector: View {
    let face: DeckFace
    let selection: String?
    let config: AppConfig?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let id = selection, let control = face.control(id) {
                Text(control.label.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)
                ForEach(Array(rows(for: control).enumerated()), id: \.offset) { _, row in
                    InspectorRow(label: row.label, title: row.title, detail: row.detail)
                }
            } else {
                Text("Nothing selected")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Click a key, strip block or knob on the deck to see what it does.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background.secondary)
    }

    private struct Row {
        let label: String
        let title: String
        let detail: String?
    }

    private func rows(for control: FaceControl) -> [Row] {
        func action(_ label: String, _ action: String?, step: Int? = nil) -> Row {
            let summary = ActionNames.summary(action ?? "none")
            let stepText = step.map { $0 > 0 ? "up \($0)" : "down \(-$0)" }
            return Row(label: label, title: summary.title, detail: [summary.detail, stepText].compactMap { $0 }.first)
        }
        switch control.kind {
        case .key, .button:
            let button = face.deck == .n4 ? config?.n4?.keys[control.id] : config?.n3?.buttons[control.id]
            return [action("Action", button?.action, step: button?.step)]
        case .knob:
            let knob = face.deck == .n4 ? config?.n4?.knobs[control.id] : config?.n3?.knobs[control.id]
            return [action("Turn", knob?.rotate.action, step: knob?.rotate.step),
                    action("Press", knob?.press.action)]
        case .stripBlock:
            let block = config?.n4?.strip[control.id]
            let shows: String
            switch block?.type {
            case .internet: shows = "Internet latency"
            case .load: shows = "CPU and memory"
            case .volume: shows = "Volume"
            case .picture: shows = "A picture"
            case .empty, nil: shows = "Nothing"
            }
            return [Row(label: "Shows", title: shows, detail: block?.type == .internet ? block?.host : nil),
                    action("Tap", block?.action, step: block?.step)]
        }
    }
}

struct InspectorRow: View {
    let label: String
    let title: String
    let detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail).foregroundStyle(.secondary).lineLimit(3).truncationMode(.middle)
                }
            }
        }
        .font(.system(size: 12.5))
    }
}

/// The line along the bottom: whether the deck controller is running, or what's wrong.
struct StatusBar: View {
    let health: AppModel.Health
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(health == .good ? Color(rgb: 0x30D158) : health == .busy ? Color(rgb: 0xFF9F0A) : Color(rgb: 0xFF453A))
                .frame(width: 6, height: 6)
            Text(text).lineLimit(1).truncationMode(.middle)
            Spacer()
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 26)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
