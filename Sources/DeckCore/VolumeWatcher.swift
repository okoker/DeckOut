import CoreAudio
import Foundation

/// Reports system volume and mute the moment either changes — knob, keyboard, menu bar, any app —
/// without polling. CoreAudio listeners: the system's default output device, plus volume and mute on
/// that device (output scope; main, 1 and 2 where the device has them). On a device switch the
/// listeners move to the new device.
///
/// Every callback just re-reads `VolumeControl.current()`, so the shown value always comes from the
/// current default device, whichever listener fired. A listener left behind on an old device can
/// only cause a redundant re-read. Main thread only.
final class VolumeWatcher {
    var onChange: ((Int?, Bool) -> Void)?

    private var running = false
    private var device: AudioDeviceID?
    private var deviceAddresses: [AudioObjectPropertyAddress] = []
    private var reportQueued = false
    private var last: (percent: Int?, muted: Bool)?

    // Stored once: removing a listener needs the very block object that was added.
    private lazy var defaultDeviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.defaultDeviceChanged()
    }
    private lazy var valueListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.queueReport()
    }

    private static var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    func start() {
        guard !running else { return }
        running = true
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress, .main, defaultDeviceListener)
        attach(to: VolumeControl.defaultOutputDevice())
        let now = VolumeControl.current()      // baseline; the first change reports
        last = (percent: now?.percent, muted: now?.muted ?? false)
    }

    func stop() {
        guard running else { return }
        running = false
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress, .main, defaultDeviceListener)
        detach()
    }

    // MARK: - Private

    private func defaultDeviceChanged() {
        guard running else { return }
        detach()
        attach(to: VolumeControl.defaultOutputDevice())
        queueReport()
    }

    private func attach(to deviceID: AudioDeviceID?) {
        guard let deviceID else { return }
        device = deviceID
        for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            for element: UInt32 in [kAudioObjectPropertyElementMain, 1, 2] {
                var address = AudioObjectPropertyAddress(
                    mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
                guard AudioObjectHasProperty(deviceID, &address) else { continue }
                if AudioObjectAddPropertyListenerBlock(deviceID, &address, .main, valueListener) == noErr {
                    deviceAddresses.append(address)
                }
            }
        }
    }

    private func detach() {
        guard let deviceID = device else { return }
        for var address in deviceAddresses {
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, .main, valueListener)
        }
        deviceAddresses = []
        device = nil
    }

    /// One change often fires several listeners (each channel, then mute); read once per run-loop pass.
    private func queueReport() {
        guard running, !reportQueued else { return }
        reportQueued = true
        DispatchQueue.main.async { [weak self] in
            self?.reportQueued = false
            self?.report()
        }
    }

    private func report() {
        guard running else { return }
        let now = VolumeControl.current()
        let reading = (percent: now?.percent, muted: now?.muted ?? false)
        if let last, last.percent == reading.percent, last.muted == reading.muted { return }
        last = reading
        onChange?(reading.percent, reading.muted)
    }
}
