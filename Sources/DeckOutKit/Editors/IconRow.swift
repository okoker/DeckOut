import DeckCore
import SwiftUI

/// Which control an icon is for: a key's square, or a strip block's wide 176 × 112.
enum IconShape: Equatable {
    case key(DeckKind)
    case stripBlock

    var previewSize: CGSize { self == .stripBlock ? CGSize(width: 88, height: 56) : CGSize(width: 56, height: 56) }

    /// The icon as the deck shows it on this control.
    func preview(_ path: String) -> CGImage? {
        switch self {
        case .key(let deck): return DeckPreview.keyImage(path: path, deck: deck)
        case .stripBlock: return DeckPreview.stripPicture(path: path)
        }
    }
}

/// Icon: the app's own (Open App), an image you choose, text on a colour, or a symbol from the library; and the
/// control as the deck will show it (mockup: [App | Image | Text | Library]). Keys and strip blocks alike: the
/// control's icon, how it was made, and how to set each come in.
struct IconRow: View {
    @ObservedObject var model: AppModel
    let shape: IconShape
    let choice: ActionChoice          // the key's action or the block's tap: App is offered for Open App
    let icon: String?
    let tile: IconTile?
    let setIcon: (String?) -> Void
    let setTile: (IconTile) -> Void
    @State private var choosingSymbol = false

    enum Source: Hashable { case app, image, text, library }

    /// The mockup's key colours.
    static let swatches = ["#0A84FF", "#30D158", "#FFD60A", "#FF9F0A", "#FF375F", "#BF5AF2", "#5E5CE6",
                           "#0F8A7E", "#C35A00", "#3A3A3C"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldRow("Icon") {
                Picker("", selection: Binding(get: { source }, set: { if let new = $0 { pick(new) } })) {
                    if isOpenApp { Text("App").tag(Optional(Source.app)) }
                    Text("Image").tag(Optional(Source.image))
                    Text("Text").tag(Optional(Source.text))
                    Text("Library").tag(Optional(Source.library))
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .fixedSize()
            }
            if let tile, source == .text {
                FieldRow("Text") {
                    CommitTextField(value: tile.text ?? "", placeholder: "Up to three lines", multiline: true) { text in
                        var changed = tile
                        changed.text = text
                        setTile(changed)
                    }
                }
                colourRows(tile)
            }
            if let tile, source == .library {
                FieldRow("Symbol") {
                    Button(tile.symbol ?? "Choose…") { choosingSymbol = true }
                        .popover(isPresented: $choosingSymbol, arrowEdge: .leading) {
                            SymbolPicker(library: model.symbolLibrary, selected: tile.symbol, style: tile.style ?? "bold") { name, style in
                                var changed = tile
                                changed.symbol = name
                                changed.style = style
                                setTile(changed)
                            }
                        }
                }
                colourRows(tile)
            }
            HStack(alignment: .top, spacing: 12) {
                preview
                VStack(alignment: .leading, spacing: 6) {
                    Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        if source == .image { Button("Choose…", action: chooseImage).controlSize(.small) }
                        if icon != nil {
                            Button("No Icon") { setIcon(nil) }
                                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
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

    private var source: Source? {
        if let tile { return tile.kind == .text ? .text : .library }
        guard let icon else { return nil }
        return isOpenApp && AppModel.followsApp(icon) ? .app : .image
    }

    private var caption: String {
        switch source {
        case .app?: return "The app's own icon, as the deck shows it."
        case .image?: return "Your image, as the deck shows it."
        case .text?, .library?: return "As the deck shows it."
        case nil: return shape == .stripBlock ? "No icon: a black block." : "No icon: a black screen."
        }
    }

    @ViewBuilder
    private func colourRows(_ tile: IconTile) -> some View {
        FieldRow("Colour") {
            HStack(spacing: 5) {
                ForEach(Self.swatches, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 15, height: 15)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(tile.background == hex ? 0.9 : 0.15),
                                                       lineWidth: tile.background == hex ? 2 : 0.5))
                        .onTapGesture {
                            var changed = tile
                            changed.background = hex
                            setTile(changed)
                        }
                        .accessibilityLabel(hex)
                        .accessibilityAddTraits(.isButton)
                }
            }
        }
        FieldRow(tile.kind == .text ? "Text colour" : "Symbol colour") {
            Picker("", selection: Binding(get: { tile.foreground ?? "auto" }, set: { value in
                var changed = tile
                changed.foreground = value == "auto" ? nil : value
                setTile(changed)
            })) {
                Text("Auto").tag("auto")
                Text("White").tag("#FFFFFF")
                Text("Black").tag("#1D1D1F")
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .fixedSize()
        }
    }

    private var preview: some View {
        ZStack {
            Color.black
            if let icon, let image = shape.preview(icon) {
                Image(decorative: image, scale: 1).resizable().interpolation(.high)
            }
        }
        .frame(width: shape.previewSize.width, height: shape.previewSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(rgb: 0x3B3B3E), lineWidth: 1.5).padding(-1))
    }

    /// The text a new text icon starts with: what the key opens or does, by name (it wraps; it's never cut).
    static func defaultText(_ choice: ActionChoice) -> String {
        switch choice {
        case .nothing: return "Key"
        case .openApp(let path) where !path.isEmpty: return ActionNames.appName(path)
        case .openFile(let path) where !path.isEmpty, .runScript(let path) where !path.isEmpty:
            return ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        case .openWebsite(let url):
            if let host = URL(string: url)?.host { return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host }
            return "Website"
        case .runShortcut(let name) where !name.isEmpty: return name
        case .keyboardShortcut(let keys) where !keys.isEmpty: return ActionNames.shortcutSymbols(keys)
        default: return choice.kind(in: .key).title
        }
    }

    private func pick(_ new: Source) {
        switch new {
        case .app:
            if case .openApp(let path) = choice, let generated = model.appIcon(for: path) { setIcon(generated) }
        case .image:
            chooseImage()
        case .text:
            setTile(IconTile(kind: .text, text: Self.defaultText(choice), symbol: nil, style: nil,
                             background: Self.swatches[0], foreground: nil))
        case .library:
            setTile(IconTile(kind: .symbol, text: nil, symbol: "star", style: "fill", background: Self.swatches[9],
                             foreground: nil))
            choosingSymbol = true
        }
    }

    private func chooseImage() {
        guard let source = Chooser.image(), let copy = model.importImage(source) else { return }
        setIcon(copy)
    }
}

/// The library: search the 1,530 symbols, Bold or Fill, click one.
struct SymbolPicker: View {
    let library: SymbolLibrary?
    let selected: String?
    @State var style: String
    let pick: (String, String) -> Void
    @State private var search = ""

    init(library: SymbolLibrary?, selected: String?, style: String, pick: @escaping (String, String) -> Void) {
        self.library = library
        self.selected = selected
        _style = State(initialValue: style)
        self.pick = pick
    }

    var body: some View {
        let names = (library?.names ?? []).filter { search.isEmpty || $0.contains(search.lowercased()) }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Search symbols", text: $search).textFieldStyle(.roundedBorder)
                Picker("", selection: $style) {
                    Text("Bold").tag("bold")
                    Text("Fill").tag("fill")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
            if let library {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 4), count: 7), spacing: 4) {
                        ForEach(names, id: \.self) { name in
                            Button { pick(name, style) } label: {
                                Text(library.character(name) ?? "?")
                                    .font(Font(library.font(SymbolLibrary.Style(rawValue: style) ?? .bold, size: 20)))
                                    .frame(width: 38, height: 38)
                                    .background(RoundedRectangle(cornerRadius: 6)
                                        .fill(name == selected ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.05)))
                            }
                            .buttonStyle(.plain)
                            .help(name)
                        }
                    }
                }
                .frame(height: 260)
                Text("\(names.count) symbols · Phosphor (MIT)").font(.system(size: 10.5)).foregroundStyle(.secondary)
            } else {
                Text(SymbolLibrary.missingText).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 360)
    }
}

extension Color {
    /// `Color(hex: "#0A84FF")`.
    init(hex: String) {
        let value = UInt32(hex.dropFirst(hex.hasPrefix("#") ? 1 : 0), radix: 16) ?? 0
        self.init(rgb: value)
    }
}
