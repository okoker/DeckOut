import AppKit

final class BrightnessHUD {

    private static var windows: [NSWindow] = []
    private static var labels: [NSTextField] = []
    private static var dismissTimer: DispatchSourceTimer?
    private static var screenCount: Int = 0
    private static let boxSize = NSSize(width: 700, height: 160)

    /// Show (or update) a large HUD overlay on ALL screens simultaneously.
    /// Auto-dismisses 2.5 s after the last call. Reuses windows when possible.
    static func show(text: String) {
        dispatchPrecondition(condition: .onQueue(.main))

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        if !labels.isEmpty && screenCount == screens.count {
            for lbl in labels { setText(text, on: lbl) }
            for win in windows { win.orderFrontRegardless() }
        } else {
            closeAll()
            for screen in screens {
                createWindow(text: text, screen: screen)
            }
            screenCount = screens.count
            print("BrightnessHUD: created \(screens.count) window(s)")
        }

        dismissTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 2.5)
        timer.setEventHandler { closeAll() }
        timer.resume()
        dismissTimer = timer
    }

    /// The usual 80 pt, or smaller so `text` fits `width`.
    static func fontSize(for text: String, width: CGFloat) -> CGFloat {
        let full: CGFloat = 80
        let measured = textWidth(text, fontSize: full)
        return measured <= width ? full : (full * width / measured).rounded(.down)
    }

    /// How wide `text` is in the HUD's font at `fontSize`.
    static func textWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)]).width
    }

    // MARK: - Private

    private static func createWindow(text: String, screen: NSScreen) {
        let winW = boxSize.width
        let winH = boxSize.height
        let sf = screen.frame
        let origin = NSPoint(x: sf.midX - winW / 2, y: sf.midY - winH / 2)

        let win = NSWindow(
            contentRect: NSRect(origin: origin, size: NSSize(width: winW, height: winH)),
            styleMask: .borderless,
            backing: .buffered,
            defer: false)
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.backgroundColor = NSColor.black.withAlphaComponent(0.80)
        win.isOpaque = false
        win.hasShadow = true
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]

        win.contentView?.wantsLayer = true
        win.contentView?.layer?.cornerRadius = 24
        win.contentView?.layer?.masksToBounds = true

        let lbl = NSTextField(labelWithString: text)
        lbl.textColor = .white
        lbl.alignment = .center
        lbl.backgroundColor = .clear
        lbl.isBezeled = false
        lbl.isEditable = false
        setText(text, on: lbl)

        win.contentView?.addSubview(lbl)
        win.orderFrontRegardless()

        windows.append(win)
        labels.append(lbl)
    }

    /// The text at a size that fits the box (20 pt in from each side), centred in it.
    private static func setText(_ text: String, on lbl: NSTextField) {
        lbl.stringValue = text
        lbl.font = NSFont.monospacedSystemFont(ofSize: fontSize(for: text, width: boxSize.width - 40), weight: .bold)
        let height = lbl.fittingSize.height
        lbl.frame = NSRect(x: 0, y: (boxSize.height - height) / 2, width: boxSize.width, height: height)
    }

    private static func closeAll() {
        dismissTimer?.cancel()
        dismissTimer = nil
        for win in windows { win.close() }
        windows.removeAll()
        labels.removeAll()
        screenCount = 0
    }
}
