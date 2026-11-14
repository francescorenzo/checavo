/// What the watt dial shows: the power entering the Mac now, on a scale that ends at what the cable carries.
public struct PowerGauge: Equatable, Sendable {
    public let watts: Double
    public let scaleMax: Int
    /// What the charger offers, marked on the dial.
    public let offeredWatts: Int?
    /// The port bringing the power; nil when nothing charges the Mac.
    public let port: String?
}

public func powerGauge(_ ports: [PortObservation]) -> PowerGauge {
    guard let p = ports.first(where: { $0.connected && $0.powerIn != nil })
            ?? ports.first(where: { $0.connected && $0.negotiatedMilliwatts != nil })
    else { return PowerGauge(watts: 0, scaleMax: 100, offeredWatts: nil, port: nil) }

    let watts = Double(p.powerIn?.milliwatts ?? 0) / 1000
    let offered = p.negotiatedMilliwatts.map { $0 / 1000 }
    // no chip: a USB-C cable carries at most 3 A, i.e. 60 W
    let cable = p.cableVDOs == nil ? 60 : CableInfo.decode(vdos: p.cableVDOs!).flatMap(maxWatts)
    let needed = max(Double(cable ?? 0), Double(offered ?? 0), watts)
    let scale = [30, 60, 100, 140, 240].first { Double($0) >= needed } ?? Int((needed / 10).rounded(.up)) * 10
    return PowerGauge(watts: watts, scaleMax: scale, offeredWatts: offered, port: p.name)
}
