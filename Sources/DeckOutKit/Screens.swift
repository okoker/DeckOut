import DeckCore
import SwiftUI

/// A full-window message: an illustration, a title, a line or two, and its buttons.
struct MessageScreen<Picture: View, Buttons: View>: View {
    let title: String
    let message: String
    @ViewBuilder let picture: () -> Picture
    @ViewBuilder let buttons: () -> Buttons

    var body: some View {
        VStack(spacing: 14) {
            picture()
                .padding(.bottom, 6)
            Text(title)
                .font(.system(size: 20, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) { buttons() }
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StageBackground())
    }
}

/// The stage's soft radial background from the mockup, in light and dark.
struct StageBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RadialGradient(colors: scheme == .dark ? [Color(rgb: 0x2C2C2E), Color(rgb: 0x1C1C1E)]
                                               : [Color(rgb: 0xFCFCFD), Color(rgb: 0xECECEF)],
                       center: UnitPoint(x: 0.5, y: 0.38), startRadius: 0, endRadius: 520)
    }
}

struct PlugInScreen: View {
    var body: some View {
        MessageScreen(title: "Plug in your deck",
                      message: "DeckOut sets up the MiraBox N4 and the TreasLin N3. Plug one in with its USB cable and it shows up here.") {
            HStack(spacing: 28) {
                DeckGlyph(deck: .n4, active: false, scale: 3)
                DeckGlyph(deck: .n3, active: false, scale: 3)
            }
        } buttons: { EmptyView() }
    }
}

struct PickDeckScreen: View {
    let pick: (DeckKind) -> Void

    var body: some View {
        MessageScreen(title: "Which deck do you want to set up?",
                      message: "Both decks are plugged in. You can switch between them at any time with the buttons at the top.") {
            HStack(spacing: 24) {
                ForEach([DeckKind.n4, .n3], id: \.self) { deck in
                    Button { pick(deck) } label: {
                        VStack(spacing: 10) {
                            DeckGlyph(deck: deck, active: true, scale: 3)
                            Text(deck.fullName).font(.system(size: 13, weight: .medium))
                        }
                        .padding(18)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.background))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        } buttons: { EmptyView() }
    }
}

struct MoveToApplicationsScreen: View {
    let message: String

    var body: some View {
        MessageScreen(title: "Move DeckOut to Applications", message: message) {
            Image(systemName: "folder").font(.system(size: 54, weight: .light)).foregroundStyle(.secondary)
        } buttons: {
            Button("Quit DeckOut") { NSApp.terminate(nil) }.keyboardShortcut(.defaultAction)
        }
    }
}

struct NeedsApprovalScreen: View {
    let openSettings: () -> Void

    var body: some View {
        MessageScreen(title: "Allow DeckOut in Login Items",
                      message: "DeckOut's deck controller runs your decks in the background. macOS keeps it switched off until you allow it: turn on DeckOut under Allow in the Background, then come back here.") {
            Image(systemName: "switch.2").font(.system(size: 50, weight: .light)).foregroundStyle(.secondary)
        } buttons: {
            Button("Open Login Items Settings", action: openSettings).keyboardShortcut(.defaultAction)
        }
    }
}

struct AgentProblemScreen: View {
    let message: String
    let tryAgain: () -> Void

    var body: some View {
        MessageScreen(title: "The deck controller isn't running", message: message) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 50, weight: .light)).foregroundStyle(.secondary)
        } buttons: {
            Button("Try Again", action: tryAgain).keyboardShortcut(.defaultAction)
        }
    }
}

struct StartingScreen: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Starting the deck controller…").font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StageBackground())
    }
}

struct OldControllerScreen: View {
    let problem: String?
    let retire: () -> Void
    let keep: () -> Void

    var body: some View {
        MessageScreen(title: "Another deck controller is installed",
                      message: "The deck controller installed by hand before DeckOut (StreamDeckController) also runs your decks. With both, every press would fire twice. Retire it to let DeckOut take over: it is stopped and its launch file is moved aside, so it can be put back; its program and your settings stay.") {
            Image(systemName: "rectangle.2.swap").font(.system(size: 50, weight: .light)).foregroundStyle(.secondary)
        } buttons: {
            Button("Not Now", action: keep)
            Button("Retire It", action: retire).keyboardShortcut(.defaultAction)
        }
        .overlay(alignment: .bottom) {
            if let problem { Text(problem).font(.system(size: 12)).foregroundStyle(.red).padding(.bottom, 40) }
        }
    }
}

struct RemovedScreen: View {
    let startAgain: () -> Void

    var body: some View {
        MessageScreen(title: "The deck controller is stopped",
                      message: "DeckOut is out of Login Items and your decks have stopped. To remove DeckOut, quit it and drag it to the Bin; your settings stay in ~/.config/vsd. To use your decks again, start it.") {
            Image(systemName: "stop.circle").font(.system(size: 50, weight: .light)).foregroundStyle(.secondary)
        } buttons: {
            Button("Quit DeckOut") { NSApp.terminate(nil) }
            Button("Start Again", action: startAgain).keyboardShortcut(.defaultAction)
        }
    }
}
