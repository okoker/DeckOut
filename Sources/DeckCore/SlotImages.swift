import CryptoKit
import Foundation

/// The images of the decks' static slots (key icons, picture blocks, blanks), each file rendered once per content.
/// Every pass reads each file's bytes again and renders only when they differ from the last pass's: a script that
/// rewrites its icon at the same path and posts a reload shows the new picture (the bytes changed, whatever the
/// file's date or size say), and a reload that changed nothing renders nothing. Live blocks are never kept here:
/// the Daemon makes their images from the latest reading every pass. Main thread only.
final class SlotImageCache {
    /// Renders a slot's content from its file's bytes; always an image (black when the bytes don't decode).
    typealias Render = (_ content: SlotContent, _ bytes: Data, _ slot: UInt8, _ model: DeckModel) -> Data

    /// What an image was rendered from (the deck kind is the outer key of `entries`).
    private struct Key: Hashable {
        let content: SlotContent
        let width: Int
        let height: Int
        let bytes: SHA256.Digest
    }

    private let render: Render
    /// Per deck kind, exactly the images the last pass used: one per slot at most, and a file no longer shown is
    /// dropped.
    private var entries: [DeckKind: [Key: Data]] = [:]

    init(render: @escaping Render = LayoutPlan.render(_:bytes:slot:model:)) {
        self.render = render
    }

    /// The image for every slot of `plan` except live blocks (`.strip`), which the caller fills from their readings.
    /// A missing or unreadable file shows black, with a log line, and nothing is kept for it: once the file
    /// appears, the next pass renders it.
    func images(plan: [UInt8: SlotContent], model: DeckModel) -> [UInt8: Data] {
        var images: [UInt8: Data] = [:]
        var used: [Key: Data] = [:]
        for (slot, content) in plan.sorted(by: { $0.key < $1.key }) {
            switch content {
            case .strip:
                continue
            case .blank:
                images[slot] = LayoutPlan.blank(slot: slot, model: model)
            case .icon(let path), .picture(let path):
                // Read whole, not mapped: a script rewriting the file mid-pass must not change these bytes.
                guard let bytes = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
                    print("Warning: could not load image at \(path)")
                    images[slot] = LayoutPlan.blank(slot: slot, model: model)
                    continue
                }
                let size = model.imageSize(slot: slot)
                let key = Key(content: content, width: size.width, height: size.height, bytes: SHA256.hash(data: bytes))
                // A miss renders from the bytes just read, never the path again: what is kept matches its key.
                let jpeg = used[key] ?? entries[model.kind]?[key] ?? render(content, bytes, slot, model)
                used[key] = jpeg
                images[slot] = jpeg
            }
        }
        entries[model.kind] = used
        return images
    }
}

/// What each slot of one deck shows: the JPEG last sent to it in full. A redraw sends only the slots whose image
/// differs from it. A slot with no record — never sent, its send failed, or the deck was cleared — counts as
/// different.
struct ShownSlots {
    private var images: [UInt8: Data] = [:]

    /// The slots of `wanted`, in slot order, whose image differs from what they show; with `everySlot`, all of them.
    func changed(_ wanted: [UInt8: Data], everySlot: Bool = false) -> [UInt8] {
        wanted.keys.sorted().filter { everySlot || images[$0] != wanted[$0] }
    }

    mutating func record(_ slot: UInt8, _ jpeg: Data) { images[slot] = jpeg }
    mutating func forget(_ slot: UInt8) { images[slot] = nil }
    mutating func forgetAll() { images.removeAll() }
}
