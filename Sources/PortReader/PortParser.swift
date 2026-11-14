import CableCore
import Foundation

/// A copy of one IORegistry entry and its subtree, so parsing can be tested without hardware.
public struct RegistryNode {
    public let className: String
    public let name: String
    public let properties: [String: Any]
    public let children: [RegistryNode]

    public init(className: String, name: String, properties: [String: Any], children: [RegistryNode]) {
        self.className = className
        self.name = name
        self.properties = properties
        self.children = children
    }

    var descendants: [RegistryNode] { children.flatMap { [$0] + $0.descendants } }
}

// Undocumented Apple Silicon class names, seen on macOS 27.0.1.
let cablePlugClass = "IOPortTransportComponentCCUSBPDSOPp"  // SOP': the cable's chip
let partnerClass = "IOPortTransportComponentCCUSBPDSOP"  // SOP: the device at the other end
let powerSourceClass = "IOPortFeaturePowerSource"
let displayPortClass = "IOPortTransportStateDisplayPort"

/// IORegistry names every port "Port-USB-C"; Description adds the location ("Port-USB-C@2").
public func portName(_ node: RegistryNode) -> String {
    node.properties["Description"] as? String ?? node.name
}

public func sortedPorts(_ nodes: [RegistryNode]) -> [RegistryNode] {
    nodes.sorted { portName($0).localizedStandardCompare(portName($1)) == .orderedAscending }
}

/// nil for ports that are not USB-C (MagSafe, HDMI, SD card).
public func parsePort(_ node: RegistryNode, secondsSinceConnect: Double) -> PortObservation? {
    guard node.properties["PortTypeDescription"] as? String == "USB-C" else { return nil }
    let name = portName(node)
    let connected = node.properties["ConnectionActive"] as? Bool ?? false
    let transports = node.properties["TransportsActive"] as? [String] ?? []
    // After unplugging, children linger for ~1 s: never report them for a disconnected port.
    guard connected else {
        return PortObservation(name: name, connected: false, transports: [], cableVDOs: nil, partner: nil,
                               negotiatedMilliwatts: nil, secondsSinceConnect: 0)
    }

    var cableVDOs: [UInt32]?
    var partner: Partner?
    var milliwatts: Int?
    var video: VideoLink?
    for child in node.descendants {
        let metadata = child.properties["Metadata"] as? [String: Any]
        let vdoData = metadata?["VDOs"] as? [Data]
        switch child.className {
        case cablePlugClass:
            // the chip answered: [] marks data we cannot decode, so assess() reports "unreadable"
            if let vdoData { cableVDOs = CableInfo.vdoWords(vdoData) ?? [] }
        case partnerClass:
            if let vdoData, let header = CableInfo.vdoWords(Array(vdoData.prefix(1)))?.first {
                partner = Partner(vendorID: metadata?["Vendor ID"] as? Int ?? Int(header & 0xFFFF),
                                  productID: metadata?["Product ID"] as? Int ?? 0,
                                  isUSBHost: header >> 31 == 1)
            }
        case powerSourceClass:
            if let option = child.properties["WinningPowerSourceOption"] as? [String: Any] {
                milliwatts = option["Max Power (mW)"] as? Int
                    ?? ((option["Voltage (mV)"] as? Int ?? 0) * (option["Max Current (mA)"] as? Int ?? 0) / 1000)
            }
        case displayPortClass:
            video = videoLink(child.properties) ?? video
        default: break
        }
    }
    return PortObservation(name: name, connected: true, transports: transports, cableVDOs: cableVDOs,
                           partner: partner, negotiatedMilliwatts: milliwatts, secondsSinceConnect: secondsSinceConnect,
                           video: video)
}

/// nil while no monitor is driven (the node exists on idle ports too, with "No Link").
func videoLink(_ properties: [String: Any]) -> VideoLink? {
    let lanes = properties["LaneCount"] as? Int ?? 0
    guard properties["Active"] as? Bool == true, lanes > 0 else { return nil }
    // IORegistry stores the frequencies as a set ("{( 5400000000 )}" in ioreg)
    let frequencies = properties["NominalSignalingFrequenciesHz"] as? NSSet
    let hz = frequencies?.compactMap { $0 as? Int }.max()
    let description = properties["LinkRateDescription"] as? String ?? ""  // "5.4 Gbps (HBR2)"
    let rateName = description.split(separator: "(").last.flatMap { $0.hasSuffix(")") ? String($0.dropLast()) : nil }
    let metadata = properties["Metadata"] as? [String: Any]
    return VideoLink(lanes: lanes, gbpsPerLane: hz.map { Double($0) / 1e9 }, rateName: rateName,
                     tunneled: properties["Tunneled"] as? Bool ?? false,
                     monitorName: metadata?["ProductName"] as? String,
                     display: (metadata?["EDID"] as? Data).flatMap(displayID(edid:)), mode: nil)
}

/// EDID bytes 8–15: manufacturer (big-endian), product and serial (little-endian).
func displayID(edid: Data) -> DisplayID? {
    guard edid.count >= 16 else { return nil }
    let b = [UInt8](edid.prefix(16))
    return DisplayID(vendor: UInt16(b[8]) << 8 | UInt16(b[9]), product: UInt16(b[11]) << 8 | UInt16(b[10]),
                     serial: UInt32(b[15]) << 24 | UInt32(b[14]) << 16 | UInt32(b[13]) << 8 | UInt32(b[12]))
}

/// Gives each port's monitor the mode it shows now; an ambiguous match gets none.
// shortcut: two identical monitors without a serial number get no mode; match by display path if it ever matters.
public func attachModes(_ ports: [PortObservation], displays: [(DisplayID, DisplayMode?)]) -> [PortObservation] {
    ports.map { port in
        guard let id = port.video?.display else { return port }
        let matches = displays.filter { $0.0 == id }
        var port = port
        port.video?.mode = matches.count == 1 ? matches[0].1 : nil
        return port
    }
}

/// Gives each port's monitor the channels of its audio output, matched on the EDID bytes macOS puts in the UID.
// shortcut: UID layout ("1EE461B1-0000-0000-…", vendor and product from EDID bytes 8-11) seen on one monitor only;
// if a monitor with speakers shows no audio, compare its UID in Audio MIDI Setup with this prefix.
public func attachAudio(_ ports: [PortObservation], outputs: [(uid: String, channels: Int)]) -> [PortObservation] {
    ports.map { port in
        guard let id = port.video?.display else { return port }
        let prefix = String(format: "%04X%02X%02X-", id.vendor, id.product & 0xFF, id.product >> 8)
        var port = port
        port.video?.audioChannels = outputs.first { $0.uid.uppercased().hasPrefix(prefix) }?.channels
        return port
    }
}

/// Gives the power the Mac measures coming in to the port it comes from, when that port is the only power input
/// (MagSafe included).
public func attachPowerIn(_ ports: [PortObservation], power: PowerIn?, inputs: Set<String>) -> [PortObservation] {
    guard let power, power.milliwatts > 0, inputs.count == 1, let name = inputs.first,
          let i = ports.firstIndex(where: { $0.name == name && $0.connected && $0.negotiatedMilliwatts != nil })
    else { return ports }
    var ports = ports
    ports[i].powerIn = power
    return ports
}

/// "Port-MagSafe 3@1/Power In/MagSafe" → "Port-MagSafe 3@1", only for the source the Mac is drawing from.
func powerInputName(_ properties: [String: Any]) -> String? {
    guard properties["WinningPowerSourceOption"] != nil,
          let description = properties["Description"] as? String,
          let port = description.split(separator: "/").first else { return nil }
    return String(port)
}

/// What to read besides the ports: only while the panel shows it, and only what the ports call for.
/// The menu bar icon needs the ports alone.
struct DetailReads: Equatable {
    var power: Bool
    var displays: Bool

    init(power: Bool, displays: Bool) {
        self.power = power
        self.displays = displays
    }

    init(panelOpen: Bool, ports: [PortObservation]) {
        power = panelOpen && ports.contains { $0.negotiatedMilliwatts != nil }
        displays = panelOpen && ports.contains { $0.video != nil }
    }
}

/// IOKit does not say when a port was connected: count from the first time we see it connected.
public struct ConnectionClock {
    private var since: [String: Date] = [:]

    public init() {}

    public mutating func update(name: String, connected: Bool, now: Date) -> Double {
        guard connected else {
            since[name] = nil
            return 0
        }
        let start = since[name] ?? now
        since[name] = start
        return now.timeIntervalSince(start)
    }
}
