import CableCore
import Observation
import PortReader
import SwiftUI

@MainActor @Observable
final class PortsModel {
    private(set) var ports: [PortObservation] = []
    private(set) var states: [PortState] = []
    /// The port the user clicked on the left; nil lets the window pick the most interesting one.
    var picked: String?
    var showDetails = false
    private let monitor = PortMonitor()

    init() {
        monitor.onChange = { [weak self] ports in
            self?.ports = ports
            self?.states = assess(ports)
        }
        // The window is open whenever the app runs (closing it quits), so everything is read.
        monitor.start()
    }

    var rawData: String { rawJSON(ports) }
}

// shortcut: one shared model instead of @State, because without Xcode the SwiftUI macros
// (@State) are missing; switch back to @State if the project moves to Xcode.
@MainActor let sharedModel = PortsModel()

/// A single-window utility: closing the window quits, like Calculator.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct CheCavoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private var model: PortsModel { sharedModel }

    var body: some Scene {
        Window("Che cavo è?", id: "main") {
            ContentView(model: model)
        }
        .windowResizability(.contentSize)
    }
}
