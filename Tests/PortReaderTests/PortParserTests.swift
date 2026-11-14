import Foundation
import Testing
import CableCore
@testable import PortReader

// Trees copied from the real IORegistry of 2026-11-14 (MacBook Pro M3, macOS 27.0.1).
func le(_ word: UInt32) -> Data { withUnsafeBytes(of: word.littleEndian) { Data($0) } }

nonisolated(unsafe) let realCableMetadata: [String: Any] = [
    "VDOs": [le(0x18602B01), le(0x000009E2), le(0x40516910), le(0x000A4640)],
    "Product Type Description": "Passive Cable", "Vendor ID": 11009, "Product ID": 16465, "VDO Count": 4,
]
nonisolated(unsafe) let chargerMetadata: [String: Any] = [
    "VDOs": [le(0x05C02B01), le(0), le(0x0000A819)], "Vendor ID": 11009, "Product ID": 0, "VDO Count": 3,
]

func usbcPort(connected: Bool = true, transports: [String] = ["CC"], children: [RegistryNode]) -> RegistryNode {
    RegistryNode(className: "AppleTCControllerType10", name: "Port-USB-C@2",
                 properties: ["PortTypeDescription": "USB-C", "ConnectionActive": connected,
                              "TransportsActive": transports, "PortNumber": 2],
                 children: children)
}

nonisolated(unsafe) let chargerTree = usbcPort(children: [
    RegistryNode(className: "IOPortTransportStateCC", name: "CC", properties: [:], children: [
        RegistryNode(className: "IOPortTransportComponentCCUSBPDSOPp", name: "SOP'",
                     properties: ["Metadata": realCableMetadata], children: []),
        RegistryNode(className: "IOPortTransportComponentCCUSBPDSOP", name: "SOP",
                     properties: ["Metadata": chargerMetadata], children: []),
    ]),
    RegistryNode(className: "IOPortFeaturePowerIn", name: "Power In", properties: [:], children: [
        RegistryNode(className: "IOPortFeaturePowerSource", name: "USB-PD [*]", properties: [
            "WinningPowerSourceOption": ["Max Current (mA)": 5000, "Max Power (mW)": 100_000, "Voltage (mV)": 20000],
        ], children: []),
        RegistryNode(className: "IOPortFeaturePowerSource", name: "Brick ID", properties: [:], children: []),
    ]),
])

@Test func realChargerTreeGivesTheObservation() throws {
    let obs = try #require(parsePort(chargerTree, secondsSinceConnect: 7))
    #expect(obs.name == "Port-USB-C@2")
    #expect(obs.connected)
    #expect(obs.transports == ["CC"])
    #expect(obs.cableVDOs == [0x18602B01, 0x000009E2, 0x40516910, 0x000A4640])
    #expect(obs.partner == Partner(vendorID: 11009, productID: 0, isUSBHost: false))
    #expect(obs.negotiatedMilliwatts == 100_000)
    #expect(obs.secondsSinceConnect == 7)
}

@Test func disconnectedPortDropsLeftoverChildren() throws {
    let tree = RegistryNode(className: chargerTree.className, name: chargerTree.name,
                            properties: chargerTree.properties.merging(["ConnectionActive": false]) { $1 },
                            children: chargerTree.children)
    let obs = try #require(parsePort(tree, secondsSinceConnect: 0))
    #expect(obs.connected == false)
    #expect(obs.cableVDOs == nil)
    #expect(obs.partner == nil)
    #expect(obs.negotiatedMilliwatts == nil)
}

@Test func sopWithoutVDOsYetGivesNoPartner() throws {
    // seen in the loop log: SOP appears ~3 s before its Metadata is filled
    let tree = usbcPort(children: [
        RegistryNode(className: "IOPortTransportStateCC", name: "CC", properties: [:], children: [
            RegistryNode(className: "IOPortTransportComponentCCUSBPDSOP", name: "SOP", properties: [:], children: []),
        ]),
    ])
    let obs = try #require(parsePort(tree, secondsSinceConnect: 1))
    #expect(obs.partner == nil)
    #expect(obs.cableVDOs == nil)
}

@Test func macAtTheOtherEndIsAUSBHost() throws {
    let macMetadata: [String: Any] = [
        "VDOs": [le(0xD50005AC), le(0), le(0x73133036)], "Vendor ID": 1452, "Product ID": 29459,
    ]
    let tree = usbcPort(transports: ["CC", "USB2"], children: [
        RegistryNode(className: "IOPortTransportStateCC", name: "CC", properties: [:], children: [
            RegistryNode(className: "IOPortTransportComponentCCUSBPDSOP", name: "SOP",
                         properties: ["Metadata": macMetadata], children: []),
        ]),
    ])
    let obs = try #require(parsePort(tree, secondsSinceConnect: 5))
    #expect(obs.partner == Partner(vendorID: 1452, productID: 29459, isUSBHost: true))
    #expect(obs.transports == ["CC", "USB2"])
}

@Test func malformedVDOsAreKeptAsUnreadable() throws {
    let tree = usbcPort(children: [
        RegistryNode(className: "IOPortTransportComponentCCUSBPDSOPp", name: "SOP'",
                     properties: ["Metadata": ["VDOs": [Data([1, 2, 3])]]], children: []),
    ])
    let obs = try #require(parsePort(tree, secondsSinceConnect: 5))
    #expect(obs.cableVDOs == [])  // chip answered, data unreadable → assess() says so
}

@Test func nonUSBCPortsAreSkipped() {
    let magsafe = RegistryNode(className: "AppleTCControllerType11", name: "Port-MagSafe 3@1",
                               properties: ["PortTypeDescription": "MagSafe 3", "ConnectionActive": true],
                               children: [])
    #expect(parsePort(magsafe, secondsSinceConnect: 0) == nil)
}

@Test func connectionClockCountsFromFirstSeenAndResetsOnUnplug() {
    var clock = ConnectionClock()
    let t0 = Date(timeIntervalSince1970: 1000)
    #expect(clock.update(name: "P1", connected: true, now: t0) == 0)
    #expect(clock.update(name: "P1", connected: true, now: t0.addingTimeInterval(4)) == 4)
    #expect(clock.update(name: "P1", connected: false, now: t0.addingTimeInterval(5)) == 0)
    #expect(clock.update(name: "P1", connected: true, now: t0.addingTimeInterval(9)) == 0)
}

@Test func portsAreNamedAndOrderedByTheirLocation() {
    // IORegistry names both ports "Port-USB-C"; only Description tells them apart
    func node(_ description: String) -> RegistryNode {
        RegistryNode(className: "AppleTCControllerType10", name: "Port-USB-C",
                     properties: ["PortTypeDescription": "USB-C", "Description": description], children: [])
    }
    #expect(portName(node("Port-USB-C@2")) == "Port-USB-C@2")
    #expect(sortedPorts([node("Port-USB-C@2"), node("Port-USB-C@1")]).map(portName) == ["Port-USB-C@1", "Port-USB-C@2"])
}

// Port-USB-C@2 with the ARZOPA monitor, 2026-11-14 (EDID cut to its 16-byte header, serial replaced with a made-up one).
nonisolated(unsafe) let arzopaEDID = Data([0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00,
                                           0x1e, 0xe4, 0x61, 0xb1, 0x78, 0x56, 0x34, 0x12])
func displayPortNode(active: Bool, lanes: Int, metadata: [String: Any]) -> RegistryNode {
    RegistryNode(className: "IOPortTransportStateDisplayPort", name: "DisplayPort", properties: [
        "Active": active, "LaneCount": lanes, "LinkRate": active ? 3 : 0, "Tunneled": false,
        "LinkRateDescription": active ? "5.4 Gbps (HBR2)" : "No Link",
        "NominalSignalingFrequenciesHz": NSSet(array: active ? [5_400_000_000] : []), "Metadata": metadata,  // a set in IORegistry
    ], children: [])
}
nonisolated(unsafe) let monitorTree = usbcPort(transports: ["CC", "DisplayPort"], children: [
    RegistryNode(className: "IOPortTransportStateCC", name: "CC", properties: [:], children: [
        RegistryNode(className: "IOPortTransportComponentCCUSBPDSOP", name: "SOP", properties: ["Metadata": [
            "VDOs": [le(0x6C00177A), le(0), le(0x11200001), le(0x19)], "Vendor ID": 6010, "Product ID": 4384,
        ] as [String: Any]], children: []),
    ]),
    displayPortNode(active: true, lanes: 4, metadata: ["EDID": arzopaEDID, "ProductName": "ARZOPA"]),
])

@Test func realMonitorTreeGivesTheVideoLink() throws {
    let obs = try #require(parsePort(monitorTree, secondsSinceConnect: 12))
    #expect(obs.cableVDOs == nil)
    #expect(obs.video == VideoLink(lanes: 4, gbpsPerLane: 5.4, rateName: "HBR2", tunneled: false,
                                   monitorName: "ARZOPA",
                                   display: DisplayID(vendor: 0x1EE4, product: 0xB161, serial: 305_419_896),
                                   mode: nil))
}

@Test func idleDisplayPortIsNoVideo() throws {
    let tree = usbcPort(children: [displayPortNode(active: false, lanes: 0, metadata: [:])])
    #expect(try #require(parsePort(tree, secondsSinceConnect: 12)).video == nil)
}

@Test func shortEDIDGivesNoDisplayID() {
    #expect(displayID(edid: Data([0, 1, 2])) == nil)
}

@Test func modeIsAttachedToTheMatchingMonitor() throws {
    let obs = try #require(parsePort(monitorTree, secondsSinceConnect: 12))
    let builtIn = (DisplayID(vendor: 0x610, product: 0xA04F, serial: 287_454_020), DisplayMode(width: 3024, height: 1964, hz: 120))
    let arzopa = (DisplayID(vendor: 0x1EE4, product: 0xB161, serial: 305_419_896), DisplayMode(width: 2560, height: 1440, hz: 180))
    #expect(attachModes([obs], displays: [builtIn, arzopa])[0].video?.mode == DisplayMode(width: 2560, height: 1440, hz: 180))
    #expect(attachModes([obs], displays: [builtIn])[0].video?.mode == nil)
}

@Test func twoIdenticalMonitorsWithoutSerialGetNoMode() {
    let id = DisplayID(vendor: 1, product: 2, serial: 0)
    var obs = PortObservation(name: "P", connected: true, transports: [], cableVDOs: nil, partner: nil,
                              negotiatedMilliwatts: nil, secondsSinceConnect: 12)
    obs.video = VideoLink(lanes: 4, gbpsPerLane: 5.4, rateName: nil, tunneled: false, monitorName: nil,
                          display: id, mode: nil)
    let displays = [(id, DisplayMode(width: 1920, height: 1080, hz: 60)), (id, DisplayMode(width: 3840, height: 2160, hz: 60))]
    #expect(attachModes([obs], displays: displays)[0].video?.mode == nil)
}

// CoreAudio UID of the ARZOPA output on 2026-11-14: EDID bytes 8-11, serial zeroed, bytes 16-23.
let arzopaAudioUID = "1EE461B1-0000-0000-1A23-0104B5241478"

@Test func audioOutputIsAttachedToTheMonitorWithTheSameEDID() throws {
    let obs = try #require(parsePort(monitorTree, secondsSinceConnect: 12))
    let other = (uid: "06104FA0-0000-0000-0000-000000000000", channels: 8)
    #expect(attachAudio([obs], outputs: [other, (uid: arzopaAudioUID, channels: 2)])[0].video?.audioChannels == 2)
    #expect(attachAudio([obs], outputs: [other])[0].video?.audioChannels == nil)
}

@Test func portWithoutVideoGetsNoAudio() {
    let obs = PortObservation(name: "P", connected: true, transports: ["CC"], cableVDOs: nil, partner: nil,
                              negotiatedMilliwatts: nil, secondsSinceConnect: 12)
    #expect(attachAudio([obs], outputs: [(uid: arzopaAudioUID, channels: 2)])[0] == obs)
}

// SMC DC-in sensors on 2026-11-14 with the iPad charger on port 1.
let smcPower = PowerIn(milliwatts: 44_820, millivolts: 19_320, milliamps: 2_320)
func plainPort(_ name: String, milliwatts: Int?) -> PortObservation {
    PortObservation(name: name, connected: true, transports: ["CC"], cableVDOs: nil, partner: nil,
                    negotiatedMilliwatts: milliwatts, secondsSinceConnect: 12)
}

@Test func measuredPowerGoesToThePortWithTheChargerContract() {
    let ports = [plainPort("Port-USB-C@1", milliwatts: 100_000), plainPort("Port-USB-C@2", milliwatts: nil)]
    let out = attachPowerIn(ports, power: smcPower, inputs: ["Port-USB-C@1"])
    #expect(out[0].powerIn == smcPower)
    #expect(out[1].powerIn == nil)
}

@Test func magSafeChargingIsNotTheMonitorsPower() {
    // MagSafe charging while a monitor offers power on USB-C: the power is MagSafe's
    let out = attachPowerIn([plainPort("Port-USB-C@1", milliwatts: 100_000)], power: smcPower,
                            inputs: ["Port-USB-C@1", "Port-MagSafe 3@1"])
    #expect(out[0].powerIn == nil)
}

@Test func noPowerInOnBatteryOrWithTwoContracts() {
    let one = [plainPort("P1", milliwatts: 100_000)]
    #expect(attachPowerIn(one, power: nil, inputs: ["P1"])[0].powerIn == nil)
    #expect(attachPowerIn(one, power: PowerIn(milliwatts: 0, millivolts: 0, milliamps: 0), inputs: ["P1"])[0].powerIn == nil)
    let two = [plainPort("P1", milliwatts: 100_000), plainPort("P2", milliwatts: 100_000)]
    #expect(attachPowerIn(two, power: smcPower, inputs: ["P1", "P2"]).allSatisfy { $0.powerIn == nil })
}

// SMC floats (watts, volts, amps) as read on the MacBook Pro M3 with the iPad charger
@Test func smcFloatsBecomeMilliunits() {
    #expect(smcPowerIn(watts: 44.82, volts: 19.32, amps: 2.32) == smcPower)
    #expect(smcPowerIn(watts: 0.004, volts: 0, amps: 0) == nil)  // on battery
    #expect(smcPowerIn(watts: nil, volts: 19.3, amps: 2.3) == nil)
    #expect(MemoryLayout<SMCKeyData>.stride == 80)  // the kernel's SMCKeyData_t
}

@Test func powerInputNameComesFromTheWinningSource() {
    #expect(powerInputName(["Description": "Port-MagSafe 3@1/Power In/MagSafe",
                            "WinningPowerSourceOption": ["Max Power (mW)": 140_000]]) == "Port-MagSafe 3@1")
    #expect(powerInputName(["Description": "Port-USB-C@1/Power In/Brick ID"]) == nil)
}

// Panel closed: only the registry, which the menu bar icon needs; displays, audio and power wait.
@Test func closedPanelReadsOnlyThePorts() {
    #expect(DetailReads(panelOpen: false, ports: [plainPort("P1", milliwatts: 60_000)]) == DetailReads(power: false, displays: false))
    var monitor = plainPort("P1", milliwatts: 60_000)
    monitor.video = VideoLink(lanes: 4, gbpsPerLane: 5.4, rateName: nil, tunneled: false, monitorName: nil, display: nil, mode: nil)
    #expect(DetailReads(panelOpen: true, ports: [monitor]) == DetailReads(power: true, displays: true))
    #expect(DetailReads(panelOpen: true, ports: [plainPort("P1", milliwatts: nil)]) == DetailReads(power: false, displays: false))
}

// A scaled HiDPI mode renders more pixels than the panel has; the cable carries the native size.
@Test func signalModeIsTheNativeSizeForScaledModes() {
    let native = (width: 3840, height: 2160)
    #expect(signalMode(DisplayMode(width: 5120, height: 2880, hz: 60), native: native) == DisplayMode(width: 3840, height: 2160, hz: 60))
    #expect(signalMode(DisplayMode(width: 3840, height: 2160, hz: 60), native: native) == DisplayMode(width: 3840, height: 2160, hz: 60))
    #expect(signalMode(DisplayMode(width: 1920, height: 1080, hz: 60), native: native) == nil)  // may be scaled up: unknown
    #expect(signalMode(DisplayMode(width: 1920, height: 1080, hz: 60), native: nil) == DisplayMode(width: 1920, height: 1080, hz: 60))
}
