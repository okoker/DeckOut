import AppKit
import SwiftUI

/// Renders a view to an image without a window: tests and design checks look at the result.
@MainActor
public enum Snapshot {
    struct Failed: Error {}

    public static func image<V: View>(_ view: V, size: CGSize, dark: Bool) -> CGImage? {
        let renderer = ImageRenderer(content: view
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = 1
        return renderer.cgImage
    }

    /// The view hosted in an offscreen window, so AppKit controls (pop-ups, buttons, fields) draw as they really
    /// look; `image(_:size:dark:)` draws those as placeholders.
    public static func windowPNG<V: View>(_ view: V, size: CGSize, dark: Bool) throws -> Data {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw Failed() }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw Failed() }
        return data
    }

    public static func png<V: View>(_ view: V, size: CGSize, dark: Bool) throws -> Data {
        guard let image = image(view, size: size, dark: dark),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw Failed() }
        return data
    }
}

extension Color {
    /// `Color(rgb: 0x303033)`.
    init(rgb: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255, opacity: opacity)
    }
}
