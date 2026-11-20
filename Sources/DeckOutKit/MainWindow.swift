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
            StatusBar(health: model.statusLine.health, text: model.statusLine.text,
                      hint: model.shown != nil ? "Changes apply at once · ⌘Z undoes" : nil)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                ForEach([DeckKind.n4, .n3], id: \.self) { deck in
                    DeckButton(deck: deck, plugged: model.connectedDecks.contains(deck), shown: model.shown == deck) {
                        model.show(deck)
                    }
                }
                if model.shown != nil {
                    PresetMenu(model: model, disabled: model.photoMode).padding(.leading, 10)
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if model.shown != nil {
                    BrightnessSlider(model: model)
                }
                if model.shown == .n4 {
                    Toggle(isOn: Binding(get: { model.photoMode },
                                         set: { $0 ? model.enterPhotoMode() : model.leavePhotoMode() })) {
                        Text("Lock Photo…")
                    }
                    .toggleStyle(.button)
                    .help("Choose, move and zoom the photo the N4 shows while your Mac is locked")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.becameActive() }
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
            if model.photoMode && deck == .n4 {
                HStack(spacing: 0) {
                    PhotoStage(model: model)
                    Divider()
                    PhotoInspector(model: model).frame(width: 300)
                }
            } else {
                DeckStage(model: model, face: DeckFace.of(deck))
            }
        }
    }
}

/// The deck on its stage, and the editor for the selected control.
struct DeckStage: View {
    @ObservedObject var model: AppModel
    let face: DeckFace

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 14) {
                DeckView(face: face, images: model.images, captions: model.captions, marks: Set(model.problems.keys),
                         selection: $model.selection)
                Text("Click a key, strip block or knob to set it up")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(StageBackground())
            .contentShape(Rectangle())
            .onTapGesture { model.selection = nil }
            Divider()
            EditorPanel(model: model, face: face)
                .frame(width: 300)
        }
    }
}

/// The line along the bottom: whether the deck controller is running, or what's wrong.
struct StatusBar: View {
    let health: AppModel.Health
    let text: String
    var hint: String? = nil

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(health == .good ? Color(rgb: 0x30D158) : health == .busy ? Color(rgb: 0xFF9F0A) : Color(rgb: 0xFF453A))
                .frame(width: 6, height: 6)
            Text(text).lineLimit(1).truncationMode(.middle)
            Spacer()
            if let hint { Text(hint).lineLimit(1) }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 26)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
