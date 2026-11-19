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

    init(model: DeckModel, device: IOHIDDevice) {
        self.model = model
        self.device = device
        reportBuffer = .allocate(capacity: Self.reportBufferSize)
        reportBuffer.initialize(repeating: 0, count: Self.reportBufferSize)
    }

    /// Start-up sequence: wake, brightness, refresh, clear every slot.
    func start(brightness: Int) {
        send(CRTCommand.makeDIS())
        setBrightness(brightness)
        send(CRTCommand.makeSTP())
        send(CRTCommand.makeCLE())
    }

    func setBrightness(_ brightness: Int) {
        send(CRTCommand.makeLIG(UInt8(clamping: brightness)))
    }

    /// Clears every slot. Only the N3's reload still uses this (until in-place redraw lands).
    func clearAll() {
        send(CRTCommand.makeCLE())
    }

    /// Sends one image to a wire slot: `BAT` header, then the JPEG in 1024-byte chunks.
    /// It shows after the next `commit()`. Stops at the first failed packet (e.g. the deck was unplugged).
    func draw(slot: UInt8, jpeg: Data) {
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
    }

    /// Shows what was drawn since the last commit.
    func commit() {
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
