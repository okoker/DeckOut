import CoreGraphics
import DeckCore
import Foundation

/// Lock photo mode: choosing, moving and zooming the N4's lock photo, shown on the real N4 meanwhile.
extension AppModel {

    public var lockPhoto: LockPhotoConfig? { config?.n4?.lockPhoto }

    /// The decoded photo (cached by path), for the drawing.
    public var lockPhotoImage: CGImage? {
        lockPhoto.flatMap { photoCache.image(for: $0.path) }
    }

    public func enterPhotoMode() {
        guard shown == .n4 else { return }
        photoMode = true
        selection = nil
        photoProblem = nil
        sendPreview(force: true)
    }

    /// Done: back to the keys; the N4 goes back to its layout.
    public func leavePhotoMode() {
        photoMode = false
        tellDeck(nil)
    }

    /// Copies the chosen photo into the config folder and starts it centred at zoom 1. False, with `photoProblem`
    /// set, when it isn't a picture (the config keeps its photo).
    @discardableResult
    public func choosePhoto(_ source: String) -> Bool {
        guard let store else { return false }
        let path: String
        do {
            path = try IconFiles.importLockPhoto(from: source, configPath: store.path)
        } catch {
            photoProblem = (error as? IconFiles.ImportError)?.description ?? error.localizedDescription
            return false
        }
        photoProblem = nil
        store.change("Choose Lock Photo") { config in
            config.ensureDeck(.n4)
            config.n4?.lockPhoto = LockPhotoConfig(path: path)
        }
        return true
    }

    /// Moves or zooms the photo, kept within its limits (it always covers the face); a run of moves or zooms is one
    /// undo step.
    public func setFraming(zoom: Double? = nil, offsetX: Double? = nil, offsetY: Double? = nil, name: String) {
        guard let current = lockPhoto, let image = photoCache.image(for: current.path) else { return }
        let wanted = LockPhotoConfig(path: current.path, zoom: zoom ?? current.zoom,
                                     offsetX: offsetX ?? current.offsetX, offsetY: offsetY ?? current.offsetY)
        let framing = LockPhoto.clamped(wanted, photo: CGSize(width: image.width, height: image.height))
        store?.change(name, coalescing: true) { $0.n4?.lockPhoto = framing }
    }

    /// Moves the photo by a drag's change since its last event, from where the photo is now: past the edge and
    /// back, it follows at once (moving from the drag's start would leave a dead zone).
    public func moveLockPhoto(by delta: CGSize) {
        guard let current = lockPhoto else { return }
        setFraming(offsetX: current.offsetX + delta.width / (LockPhoto.canvas.width / 2),
                   offsetY: current.offsetY + delta.height / (LockPhoto.canvas.height / 2), name: "Move Lock Photo")
    }

    public func resetFraming() {
        guard let current = lockPhoto else { return }
        store?.change("Reset Lock Photo") { $0.n4?.lockPhoto = LockPhotoConfig(path: current.path) }
    }

    public func removePhoto() {
        store?.change("Remove Lock Photo") { $0.n4?.lockPhoto = nil }
    }

    /// Puts the current framing on the N4 (or takes it off), at most every 50 ms during a drag; the last one is
    /// always sent.
    func sendPreview(force: Bool = false) {
        guard photoMode else { return }
        let wait = 0.05 - Date().timeIntervalSince(lastPreviewSent)
        if force || wait <= 0 {
            lastPreviewSent = Date()
            tellDeck(showOnDeck ? lockPhoto : nil)
        } else if !previewScheduled {
            previewScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                guard let self else { return }
                self.previewScheduled = false
                self.sendPreview(force: true)
            }
        }
    }

    /// Puts `framing` on the N4, or its keys back for nil, and remembers what it was told.
    private func tellDeck(_ framing: LockPhotoConfig?) {
        deckPreview = .some(framing)
        let data = framing.flatMap { try? JSONEncoder().encode($0) }
        link?.call({ proxy in proxy.showLockPhoto(data) {} })
    }
}
