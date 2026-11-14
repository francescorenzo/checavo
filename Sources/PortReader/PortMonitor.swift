import CableCore
import Foundation

/// Reads the USB-C ports once a second and reports what it sees.
/// A timer is needed anyway: "still reading" turns into "no chip" after a timeout, with no IOKit event.
@MainActor
public final class PortMonitor {
    public var onChange: (([PortObservation]) -> Void)?
    private var clock = ConnectionClock()
    private var timer: Timer?
    private var last: [PortObservation] = []
    private let smc = SMC()
    /// The app closes it while the panel is hidden; the command-line dump keeps reading everything.
    public var panelOpen = true

    public init() {}

    public func readNow(now: Date = Date()) -> [PortObservation] {
        var ports = readRegistryPorts().compactMap { node in
            let connected = node.properties["ConnectionActive"] as? Bool ?? false
            let seconds = clock.update(name: portName(node), connected: connected, now: now)
            return parsePort(node, secondsSinceConnect: seconds)
        }
        let reads = DetailReads(panelOpen: panelOpen, ports: ports)
        if reads.power { ports = attachPowerIn(ports, power: smc.powerIn(), inputs: powerInputs()) }
        guard reads.displays else { return ports }
        return attachAudio(attachModes(ports, displays: onlineDisplays()), outputs: displayAudioOutputs())
    }

    public func start() {
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Reads now instead of at the next tick: the panel just opened.
    public func refresh() { tick() }

    private func tick() {
        let ports = readNow()
        // seconds tick every time; while a port waits for its chip they matter for the verdict
        guard ports != last else { return }
        last = ports
        onChange?(ports)
    }
}
