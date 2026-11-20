import Foundation

/// What one image slot shows.
enum SlotContent: Hashable {
    case icon(String)               // a key's icon file
    case picture(String)            // a `picture` strip block
    case strip(StripBlockType)      // a live strip block (internet, load, volume), drawn from its latest reading
    case blank
}

/// Every image slot of a deck and what it shows. Every redraw (start-up, reload, unlock) makes an image for each
/// slot of this plan — icons through `SlotImageCache`, which reads each file's bytes again and renders only when
/// they changed; live blocks from their latest reading — and sends only the slots whose image differs from what the
/// deck shows (`ShownSlots`); unlock sends every slot.
enum LayoutPlan {

    static func slots(model: DeckModel, config: AppConfig) -> [UInt8: SlotContent] {
        var plan: [UInt8: SlotContent] = [:]
        let keys: [String: ButtonConfig]
        switch model.kind {
        case .n3: keys = config.n3?.buttons ?? [:]
        case .n4: keys = config.n4?.keys ?? [:]
        }
        for (key, slot) in model.keySlots {
            plan[slot] = keys[key]?.icon.map { .icon($0) } ?? .blank
        }
        for (block, slot) in model.stripSlots {
            guard let blockConfig = config.n4?.strip[block] else {
                plan[slot] = .blank
                continue
            }
            switch blockConfig.type {
            case .internet, .load, .volume: plan[slot] = .strip(blockConfig.type)
            case .picture:                  plan[slot] = blockConfig.icon.map { .picture($0) } ?? .blank
            case .empty:                    plan[slot] = .blank
            }
        }
        return plan
    }

    /// The image for a static slot. Always an image: a missing or unreadable file, and live blocks
    /// (drawn by the Daemon from their readings), fall back to black at the slot's size.
    static func render(_ content: SlotContent, slot: UInt8, model: DeckModel) -> Data {
        let image: Data?
        switch content {
        case .icon(let path):
            image = model.kind == .n3 ? ImageLoader.loadAsJPEG(path: path) : IconImage.renderN4(path: path)
        case .picture(let path):
            image = StripRenderer.picture(path: path)
        case .strip, .blank:
            image = nil
        }
        return image ?? blank(slot: slot, model: model)
    }

    /// The same from the file's bytes, already read (`SlotImageCache` renders this way, so the image it keeps is
    /// always the one for the bytes it read).
    static func render(_ content: SlotContent, bytes: Data, slot: UInt8, model: DeckModel) -> Data {
        let image: Data?
        switch content {
        case .icon(let path):
            image = model.kind == .n3 ? ImageLoader.loadAsJPEG(data: bytes, path: path)
                                      : IconImage.renderN4(data: bytes, path: path)
        case .picture(let path):
            image = StripRenderer.picture(data: bytes, path: path)
        case .strip, .blank:
            image = nil
        }
        return image ?? blank(slot: slot, model: model)
    }

    /// A black image at the slot's size.
    static func blank(slot: UInt8, model: DeckModel) -> Data {
        let size = model.imageSize(slot: slot)
        return StripRenderer.blank(w: size.width, h: size.height)
    }
}
