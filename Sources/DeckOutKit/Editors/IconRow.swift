import DeckCore
import SwiftUI

/// Icon: the app's own (Open App), an image you choose, or none; and the key as the deck will show it.
struct IconRow: View {
    @ObservedObject var model: AppModel
    let deck: DeckKind
    let id: String
    let choice: ActionChoice
    let icon: String?

    enum Source: Hashable { case app, image, none }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldRow("Icon") {
                Picker("", selection: Binding(get: { source }, set: pick)) {
                    if isOpenApp { Text("App").tag(Source.app) }
                    Text("Image").tag(Source.image)
                    Text("None").tag(Source.none)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
            HStack(alignment: .top, spacing: 12) {
                preview
                VStack(alignment: .leading, spacing: 6) {
                    Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if source == .image {
                        Button("Choose…", action: chooseImage).controlSize(.small)
                    }
                }
            }
            .padding(.leading, FieldRow<EmptyView>.labelWidth + 10)
            if let problem = model.iconProblem { FieldNote(text: problem, warning: true) }
        }
    }

    private var isOpenApp: Bool {
        if case .openApp(let path) = choice { return !path.isEmpty }
        return false
    }

    private var source: Source {
        guard let icon else { return .none }
        return isOpenApp && AppModel.followsApp(icon) ? .app : .image
    }

    private var caption: String {
        switch source {
        case .app: return "The app's own icon, as the deck shows it."
        case .image: return "Your image, as the deck shows it."
        case .none: return "A black screen."
        }
    }

    private var preview: some View {
        ZStack {
            Color.black
            if let icon, let image = DeckPreview.keyImage(path: icon, deck: deck) {
                Image(decorative: image, scale: 1).resizable().interpolation(.high)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(rgb: 0x3B3B3E), lineWidth: 1.5).padding(-1))
    }

    private func pick(_ new: Source) {
        switch new {
        case .app:
            if case .openApp(let path) = choice, let generated = model.appIcon(for: path) {
                model.setIcon(generated, button: id, on: deck)
            }
        case .image: chooseImage()
        case .none: model.setIcon(nil, button: id, on: deck)
        }
    }

    private func chooseImage() {
        guard let source = Chooser.image(), let copy = model.importImage(source) else { return }
        model.setIcon(copy, button: id, on: deck)
    }
}
