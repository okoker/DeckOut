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
