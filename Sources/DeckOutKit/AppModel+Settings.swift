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

    /// Lists the monitors (`m1ddc display list detailed`) and checks each answers a brightness read (`display N get
    /// luminance`, read only, 3 s each at most), off the main thread.
    public func loadMonitors() {
        guard let path = m1ddcPath else {
            monitorsNote = "m1ddc isn't in this build, so monitors can't be listed."
            return
        }
        monitorsNote = "Looking for monitors…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var found = MonitorList.parse(Self.run(path, ["display", "list", "detailed"])?.output ?? "")
            for index in found.indices {
                let reading = Self.run(path, ["display", "\(found[index].number)", "get", "luminance"], timeout: 3)
                found[index].answers = reading.map { MonitorList.answers(output: $0.output, exitStatus: $0.status) } ?? false
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.monitors = found
                let frames = MonitorList.screenFrames().filter { id, _ in found.contains { $0.displayID == id } }
                self.monitorPlaces = MonitorList.places(frames)
                self.monitorsNote = found.isEmpty ? "No external monitors found." : nil
            }
        }
    }

    /// Runs m1ddc and returns what it printed and its exit status; nil if it couldn't start or ran past `timeout`.
    nonisolated static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 10) -> (output: String, status: Int32)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer.cancel()
        guard process.terminationReason == .exit else { return nil }
        return (String(decoding: data, as: UTF8.self), process.terminationStatus)
    }

    /// The monitors as Settings lists them: the ones in use in Switch Monitor's order, then the rest.
    public var monitorsInOrder: [Monitor] { MonitorList.ordered(monitors, displays: config?.displays) }

    /// "~/.config/vsd" (dev: "~/.config/vsd-dev"), for messages.
    public var configFolderForPeople: String {
        identity?.isDev == true ? "~/.config/vsd-dev" : "~/.config/vsd"
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
