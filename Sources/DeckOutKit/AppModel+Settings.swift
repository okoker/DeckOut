import AppKit
import DeckCore
import Foundation

/// Settings: monitors for the brightness keys, the deck controller's state.
extension AppModel {

    /// The m1ddc the app and its agent use: the app's own, else Homebrew's.
    var m1ddcPath: String? {
        [Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/m1ddc").path,
         "/opt/homebrew/bin/m1ddc", "/usr/local/bin/m1ddc"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Lists the monitors (`m1ddc display list detailed`, read only), off the main thread.
    public func loadMonitors() {
        guard let path = m1ddcPath else {
            monitorsNote = "m1ddc isn't in this build, so monitors can't be listed."
            return
        }
        monitorsNote = "Looking for monitors…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["display", "list", "detailed"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            var found: [Monitor] = []
            if (try? process.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                found = MonitorList.parse(String(decoding: data, as: UTF8.self))
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.monitors = found
                let frames = MonitorList.screenFrames().filter { id, _ in found.contains { $0.displayID == id } }
                self.monitorPlaces = MonitorList.places(frames)
                self.monitorsNote = found.isEmpty ? "No external monitors that answer to brightness control." : nil
            }
        }
    }

    /// "LG HDR 4K · Left".
    public func monitorLabel(_ monitor: Monitor) -> String {
        let place = monitorPlaces[monitor.displayID] ?? ""
        return place.isEmpty ? monitor.name : "\(monitor.name) · \(place)"
    }

    public func displayConfig(_ serial: String) -> DisplayConfig? {
        config?.displays?.first { $0.serial == serial }
    }

    public func useMonitor(_ monitor: Monitor, _ use: Bool) {
        let place = monitorPlaces[monitor.displayID] ?? ""
        store?.change(use ? "Use Monitor" : "Stop Using Monitor") {
            $0.useMonitor(serial: monitor.serial, name: place.isEmpty ? monitor.name : place, use)
        }
    }

    public func renameMonitor(_ serial: String, to name: String) {
        store?.change("Rename Monitor") { $0.renameMonitor(serial: serial, to: name) }
    }

    public func moveMonitor(_ serial: String, up: Bool) {
        store?.change("Reorder Monitors") { $0.moveMonitor(serial: serial, up: up) }
    }

    /// The shell environment read again (Settings → Read Again).
    public func refreshEnvironment() {
        link?.call({ proxy in proxy.refreshEnvironment { _ in } })
    }
}
