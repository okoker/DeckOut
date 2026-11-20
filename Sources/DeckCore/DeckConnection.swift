import Foundation
import IOKit
import IOKit.hid

/// One plugged-in deck: the packets sent to it and the buffer its input reports land in.
/// Created and closed by `DeckManager`; used on the main thread only.
final class DeckConnection {
    let model: DeckModel
    let device: IOHIDDevice

    /// IOKit writes input reports here. Registered by `DeckManager`; unregistered and freed in `close()`.
    let reportBuffer: UnsafeMutablePointer<UInt8>
    static let reportBufferSize = 512

    private(set) var isOpen = true
    /// What each slot shows, as last sent: a redraw sends only what differs.
    private var shown = ShownSlots()

    init(model: DeckModel, device: IOHIDDevice) {
        self.model = model
        self.device = device
        reportBuffer = .allocate(capacity: Self.reportBufferSize)
        reportBuffer.initialize(repeating: 0, count: Self.reportBufferSize)
    }

    /// Start-up sequence: wake, brightness, refresh, clear every slot (so the next redraw sends every slot).
    func start(brightness: Int) {
        send(CRTCommand.makeDIS())
        setBrightness(brightness)
        send(CRTCommand.makeSTP())
        send(CRTCommand.makeCLE())
        shown.forgetAll()
    }

    func setBrightness(_ brightness: Int) {
        send(CRTCommand.makeLIG(UInt8(clamping: brightness)))
    }

    /// Clears every slot (so the next redraw sends every slot). After start-up only for a model with
    /// `clearsBeforeRedraw`.
    func clearAll() {
        send(CRTCommand.makeCLE())
        shown.forgetAll()
    }

    /// Sends the slots of `images` whose image differs from what they show (with `everySlot`, all of them), then
    /// one commit if it sent any. If the commit fails, the slots just sent are forgotten (the deck may still show
    /// their old images), so the next redraw sends them again. Returns how many it sent.
    @discardableResult
    func drawChanged(_ images: [UInt8: Data], everySlot: Bool) -> Int {
        let slots = shown.changed(images, everySlot: everySlot)
        for slot in slots {
            if let jpeg = images[slot] { draw(slot: slot, jpeg: jpeg) }
        }
        if !slots.isEmpty, !commit() { slots.forEach { shown.forget($0) } }
        return slots.count
    }

    /// Sends one image to a wire slot: `BAT` header, then the JPEG in 1024-byte chunks.
    /// It shows after the next `commit()`. Stops at the first failed packet (e.g. the deck was unplugged).
    /// The slot's image is recorded as shown only when every packet went out (and stays recorded only if the
    /// commit then goes out too); otherwise the slot is forgotten, so the next redraw sends it again.
    private func draw(slot: UInt8, jpeg: Data) {
        shown.forget(slot)
        guard !jpeg.isEmpty else { return }
        guard jpeg.count <= 65535 else {
            print("Warning: \(model.kind.rawValue) slot \(slot): image too large (\(jpeg.count) bytes, max 65535)")
            return
        }
        guard send(CRTCommand.makeBAT(imageLength: jpeg.count, slot: slot)) else { return }
        let bytes = [UInt8](jpeg)
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + 1024, bytes.count)
            guard send(CRTCommand.makeDataChunk(data: Array(bytes[offset..<end]))) else { return }
            offset = end
        }
        shown.record(slot, jpeg)
    }

    /// Shows what was drawn since the last commit. False if the packet didn't go out.
    private func commit() -> Bool {
        send(CRTCommand.makeSTP())
    }

    func keepalive() {
        send(CRTCommand.makeCONNECT())
    }

    /// Stops input delivery and frees the buffer. Safe to call twice.
    func close() {
        guard isOpen else { return }
        isOpen = false
        IOHIDDeviceRegisterInputReportCallback(device, reportBuffer, Self.reportBufferSize, nil, nil)
        reportBuffer.deallocate()
    }

    /// Byte 0 is the report ID; IOKit takes the data without it.
    @discardableResult
    private func send(_ packet: [UInt8]) -> Bool {
        guard isOpen, !packet.isEmpty else { return false }
        let reportID = CFIndex(packet[0])
        let payload = Array(packet.dropFirst())
        let result = payload.withUnsafeBufferPointer { buf -> IOReturn in
            guard let ptr = buf.baseAddress else { return kIOReturnBadArgument }
            return IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, reportID, ptr, buf.count)
        }
        if result != kIOReturnSuccess {
            print("Warning: \(model.kind.rawValue) send failed with code \(result)")
            return false
        }
        return true
    }
}
