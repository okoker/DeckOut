import Foundation
import IOKit
import IOKit.hid

/// Finds supported decks and keeps one `DeckConnection` per plugged-in deck.
///
/// HID isolation: the manager matches only the vendor interface (usage page 0xFFA0, usage 1) of the
/// models in `DeckModel.all`, and re-checks a matched device's IDs before using it. The decks'
/// keyboard interfaces and every other HID device are never opened.
///
/// The IOKit callbacks carry this manager as their context; the device reference in each callback
/// picks the connection. Everything runs on the main run loop.
final class DeckManager {
    var onConnect: ((DeckConnection) -> Void)?
    var onRemove: ((DeckConnection) -> Void)?
    var onInput: ((DeckKind, DeckInput) -> Void)?

    private(set) var connections: [DeckConnection] = []
    private var manager: IOHIDManager?

    func start() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        let matching: [[String: Any]] = DeckModel.all.map { model in
            [
                kIOHIDVendorIDKey as String: model.vendorID,
                kIOHIDProductIDKey as String: model.productID,
                kIOHIDDeviceUsagePageKey as String: model.usagePage,
                kIOHIDDeviceUsageKey as String: model.usage,
            ]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        // SAFETY: the Daemon owns this manager and lives for the whole process, so an unretained
        // pointer as the callback context never dangles. Connections come and go; the context doesn't.
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceMatchedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceRemovedCallback, context)

        // Must be the main thread's run loop: input only arrives while CFRunLoopRun() runs there.
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            print("Error: IOHIDManagerOpen failed with code \(result)")
        }
    }

    /// The model a matched device belongs to, re-checked from its own properties. Nil for anything else.
    static func model(for device: IOHIDDevice) -> DeckModel? {
        func int(_ key: String) -> Int? { IOHIDDeviceGetProperty(device, key as CFString) as? Int }
        let vid = int(kIOHIDVendorIDKey), pid = int(kIOHIDProductIDKey)
        let page = int(kIOHIDPrimaryUsagePageKey), usage = int(kIOHIDPrimaryUsageKey)
        return DeckModel.all.first {
            vid == $0.vendorID && pid == $0.productID && page == $0.usagePage && usage == $0.usage
        }
    }

    // MARK: - Callbacks (main thread)

    fileprivate func deviceMatched(_ device: IOHIDDevice) {
        guard let model = Self.model(for: device) else {
            print("Ignoring a matched HID device whose IDs or usage don't match a supported deck")
            return
        }
        guard !connections.contains(where: { $0.device === device }) else { return }

        let connection = DeckConnection(model: model, device: device)
        connections.append(connection)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device, connection.reportBuffer, DeckConnection.reportBufferSize, inputReportCallback, context)
        print("Deck connected: \(model.kind.rawValue)")
        onConnect?(connection)
    }

    fileprivate func deviceRemoved(_ device: IOHIDDevice) {
        guard let index = connections.firstIndex(where: { $0.device === device }) else { return }
        let connection = connections.remove(at: index)
        connection.close()
        print("Deck disconnected: \(connection.model.kind.rawValue), waiting for reconnect...")
        onRemove?(connection)
    }

    fileprivate func inputReport(from device: IOHIDDevice, _ report: UnsafeMutablePointer<UInt8>, length: Int) {
        guard let connection = connections.first(where: { $0.device === device }), connection.isOpen else { return }
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))
        if let input = connection.model.decode(bytes) {
            onInput?(connection.model.kind, input)
        } else if bytes.count >= 11, bytes[9] != 0 {
            print("Input \(connection.model.kind.rawValue): ignored code 0x\(String(bytes[9], radix: 16)) state \(bytes[10])")
        }
    }
}

// MARK: - C callbacks

private func deviceMatchedCallback(context: UnsafeMutableRawPointer?, result: IOReturn,
                                   sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    guard let context else { return }
    Unmanaged<DeckManager>.fromOpaque(context).takeUnretainedValue().deviceMatched(device)
}

private func deviceRemovedCallback(context: UnsafeMutableRawPointer?, result: IOReturn,
                                   sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    guard let context else { return }
    Unmanaged<DeckManager>.fromOpaque(context).takeUnretainedValue().deviceRemoved(device)
}

private func inputReportCallback(context: UnsafeMutableRawPointer?, result: IOReturn,
                                 sender: UnsafeMutableRawPointer?, type: IOHIDReportType,
                                 reportID: UInt32, report: UnsafeMutablePointer<UInt8>, reportLength: CFIndex) {
    guard result == kIOReturnSuccess, reportLength >= 11, let context, let sender else { return }
    let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
    Unmanaged<DeckManager>.fromOpaque(context).takeUnretainedValue()
        .inputReport(from: device, report, length: Int(reportLength))
}
