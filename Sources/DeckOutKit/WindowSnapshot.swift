import AppKit

#if DEBUG
/// Debug builds: `--snapshot <png> [--dark] [--select <control>] [--after <seconds>]` draws the real main window,
/// title bar and toolbar included, to a PNG and quits. For design checks and test sessions without a screen
/// recording permission: a window may draw itself.
@MainActor
enum WindowSnapshot {
    static func scheduleIfAsked(model: AppModel, arguments: [String] = CommandLine.arguments) {
        guard let flag = arguments.firstIndex(of: "--snapshot"), flag + 1 < arguments.count else { return }
        let path = arguments[flag + 1]
        func value(_ name: String) -> String? {
            arguments.firstIndex(of: name).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
        }
        if arguments.contains("--dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        let after = value("--after").flatMap(Double.init) ?? 4
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, after - 1)) {
            if let id = value("--select") { model.selection = id }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + after) {
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                  let frameView = window.contentView?.superview,
                  let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else {
                print("DeckOut: snapshot failed: no window")
                exit(1)
            }
            frameView.cacheDisplay(in: frameView.bounds, to: rep)
            do {
                try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                print("DeckOut: snapshot written to \(path)")
                exit(0)
            } catch {
                print("DeckOut: snapshot failed: \(error)")
                exit(1)
            }
        }
    }
}
#endif
