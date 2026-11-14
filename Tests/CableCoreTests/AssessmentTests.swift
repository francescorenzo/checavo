import Testing
@testable import CableCore

// Values seen on the real Mac on 2026-11-14 (see fixtures/ and the ports log).
let chargerCableVDOs: [UInt32] = [0x18602B01, 0x000009E2, 0x40516910, 0x000A4640]
let applePowerBrick = Partner(vendorID: 11009, productID: 0, isUSBHost: false)  // header 0x05C02B01
let thisMac = Partner(vendorID: 1452, productID: 29459, isUSBHost: true)  // header 0xD50005AC

func port(_ name: String = "Port-USB-C@1", connected: Bool = true, transports: [String] = ["CC"],
          vdos: [UInt32]? = nil, partner: Partner? = nil, milliwatts: Int? = nil,
          seconds: Double = 30, video: VideoLink? = nil, powerIn: PowerIn? = nil) -> PortObservation {
    var p = PortObservation(name: name, connected: connected, transports: transports, cableVDOs: vdos,
                            partner: partner, negotiatedMilliwatts: milliwatts, secondsSinceConnect: seconds,
                            video: video)
    p.powerIn = powerIn
    return p
}

func report(_ state: PortState) -> CableReport? {
    if case .report(let r) = state { return r }
    return nil
}

@Test func realCableOnChargerGivesTheFourAnswers() throws {
    let states = assess([port(vdos: chargerCableVDOs, partner: applePowerBrick, milliwatts: 100_000)])
    let r = try #require(report(states[0]))
    #expect(r.headline == "Cavo che regge 240 W, solo USB 2.0, lungo circa 1–2 m")
    #expect(r.charging.verdict == .yes)
    #expect(r.charging.summary == "Fino a 240 W")
    #expect(r.charging.certainty == .declared)
    #expect(r.charging.detail.contains("100 W"))
    #expect(r.video.verdict == .no)
    #expect(r.audio.verdict == .yes)
    #expect(r.data.verdict == .partial)
    #expect(r.data.summary.contains("480 Mbit/s"))
    #expect(r.isLoopback == false)
}

@Test func emptyPortIsEmpty() {
    #expect(assess([port(connected: false)])[0] == .empty)
}

@Test func disconnectedPortIgnoresLeftoverChildren() {
    // seen in the log: after unplugging, SOP stays for ~1 s
    #expect(assess([port(connected: false, vdos: chargerCableVDOs, partner: applePowerBrick)])[0] == .empty)
}

@Test func cableWithFreeEndIsRecognised() {
    #expect(assess([port(seconds: 5)])[0] == .cableOnlyFreeEnd)
}

@Test func justPluggedPortIsStillReading() {
    #expect(assess([port(seconds: 1)])[0] == .reading)
    #expect(assess([port(partner: applePowerBrick, seconds: 3)])[0] == .reading)
}

@Test func noChipAfterTimeoutGivesInferredAnswers() throws {
    let r = try #require(report(assess([port(partner: applePowerBrick, milliwatts: 60_000, seconds: 12)])[0]))
    #expect(r.headline == "Cavo senza chip di identificazione")
    #expect(r.charging.summary == "Fino a 60 W")
    #expect(r.charging.certainty == .inferred)
    // a chipless cable carried 4-lane DisplayPort on 2026-11-14: without a chip, video is unknown, not "no"
    #expect(r.video.verdict == .unknown)
    #expect(r.video.detail.contains("monitor"))
    #expect(r.data.verdict == .unknown)
    #expect(r.data.summary.contains("480") == false)
}

@Test func unreadableChipDataSaysSo() throws {
    let r = try #require(report(assess([port(vdos: [1, 2], partner: applePowerBrick)])[0]))
    #expect(r.headline == "Dati del cavo non leggibili")
    #expect(r.charging.verdict == .unknown)
}

@Test func loopbackBetweenTwoPortsIsRecognised() throws {
    let states = assess([
        port("Port-USB-C@1", transports: ["CC", "USB2"], partner: thisMac, milliwatts: 15_000),
        port("Port-USB-C@2", transports: ["CC", "USB2"], vdos: chargerCableVDOs, partner: thisMac),
    ])
    #expect(states[0] == .loopbackOtherEnd("Port-USB-C@2"))
    let r = try #require(report(states[1]))
    #expect(r.isLoopback)
    #expect(r.audio.certainty == .measured)
    #expect(r.data.certainty == .measured)
    #expect(r.notes.contains { $0.contains("Stacca il cavo") })
    #expect(r.charging.detail.contains("15 W") == false)  // the 15 W of the loop are not the cable's limit
}

@Test func loopbackWithoutChipAndWithoutDataWiresIsChargeOnly() throws {
    let states = assess([
        port("Port-USB-C@1", partner: thisMac, milliwatts: 15_000, seconds: 12),
        port("Port-USB-C@2", partner: thisMac, seconds: 12),
    ])
    let r = try #require(report(states[0]))
    #expect(r.isLoopback)
    #expect(r.data.verdict == .no)
    #expect(r.data.certainty == .measured)
    #expect(r.audio.verdict == .no)
    #expect(states[1] == .loopbackOtherEnd("Port-USB-C@1"))
}

@Test func loopbackWithoutChipButWithDataWires() throws {
    let states = assess([
        port("Port-USB-C@1", transports: ["CC", "USB2"], partner: thisMac, seconds: 12),
        port("Port-USB-C@2", transports: ["CC", "USB2"], partner: thisMac, seconds: 12),
    ])
    let r = try #require(report(states[0]))
    #expect(r.data.verdict == .partial)
    #expect(r.data.certainty == .measured)
    #expect(r.data.summary.hasPrefix("Almeno"))  // USB 2.0 is proven; faster wires are not ruled out
    #expect(r.audio.verdict == .yes)
}

@Test func twoDifferentAppleDevicesAreNotALoop() throws {
    let other = Partner(vendorID: 1452, productID: 4096, isUSBHost: true)
    let states = assess([
        port("Port-USB-C@1", vdos: chargerCableVDOs, partner: thisMac),
        port("Port-USB-C@2", vdos: chargerCableVDOs, partner: other),
    ])
    #expect(try #require(report(states[0])).isLoopback == false)
    #expect(try #require(report(states[1])).isLoopback == false)
}

@Test func twoIdenticalChargersAreNotALoop() throws {
    let states = assess([
        port("Port-USB-C@1", vdos: chargerCableVDOs, partner: applePowerBrick),
        port("Port-USB-C@2", vdos: chargerCableVDOs, partner: applePowerBrick),
    ])
    #expect(try #require(report(states[0])).isLoopback == false)
}

@Test(arguments: [
    (CableSpeed.gen1, "Fino a 4K a 60 Hz"),
    (.gen2, "Fino a 4K a 120 Hz o 5K a 60 Hz"),
    (.gen3, "Fino a 6K a 60 Hz (8K con compressione)"),
    (.gen4, "Fino a 8K a 60 Hz"),
])
func videoLimitFollowsCableSpeed(speed: CableSpeed, expected: String) throws {
    let vdos: [UInt32] = [0x18602B01, 0, 0, UInt32(speed.rawValue) | (1 << 5)]
    let r = try #require(report(assess([port(vdos: vdos)])[0]))
    #expect(r.video.verdict == .yes)
    #expect(r.video.summary == expected)
}

@Test(arguments: [
    (UInt32(1 << 5), 60),  // 3 A, 20 V
    (UInt32(2 << 5), 100),  // 5 A, 20 V
    (UInt32(2 << 5) | (3 << 9) | (1 << 17), 240),  // 5 A, 50 V, EPR
    (UInt32(2 << 5) | (3 << 9), 100),  // 5 A, 50 V but no EPR
])
func chargingWattsFollowCurrentAndVoltage(cableVDO: UInt32, watts: Int) throws {
    let r = try #require(report(assess([port(vdos: [0x18602B01, 0, 0, cableVDO])])[0]))
    #expect(r.charging.summary == "Fino a \(watts) W")
}

// Seen on 2026-11-14: ARZOPA monitor on a chipless cable, DisplayPort 4 lanes HBR2, 2560×1440 at 180 Hz.
let arzopaLink = VideoLink(lanes: 4, gbpsPerLane: 5.4, rateName: "HBR2", tunneled: false, monitorName: "ARZOPA",
                           display: DisplayID(vendor: 0x1EE4, product: 0xB161, serial: 305_419_896),
                           mode: DisplayMode(width: 2560, height: 1440, hz: 180))
let arzopa = Partner(vendorID: 6010, productID: 4384, isUSBHost: false)

@Test func monitorOnChiplessCableMeasuresTheVideo() throws {
    let r = try #require(report(assess([port(transports: ["CC", "DisplayPort"], partner: arzopa, seconds: 12,
                                             video: arzopaLink)])[0]))
    #expect(r.video.verdict == .yes)
    #expect(r.video.certainty == .measured)
    #expect(r.video.summary.contains("2560×1440 a 180 Hz"))
    #expect(r.video.detail.contains("ARZOPA"))
    #expect(r.video.detail.contains("4 linee"))
    #expect(r.video.detail.contains("HBR2"))
    #expect(r.video.detail.contains("4K a 60 Hz"))
    // the video runs on the fast wire pairs, so the cable has them
    #expect(r.data.summary.contains("fili veloci"))
    #expect(r.data.certainty == .inferred)  // deduced from the video, not a data transfer
}

@Test func measuredVideoBeatsAChipThatSaysUSB2Only() throws {
    let r = try #require(report(assess([port(transports: ["CC", "DisplayPort"], vdos: chargerCableVDOs,
                                             video: arzopaLink)])[0]))
    #expect(r.video.verdict == .yes)
    #expect(r.video.certainty == .measured)
}

@Test func videoWithoutModeOrRateStillSaysYes() throws {
    let link = VideoLink(lanes: 2, gbpsPerLane: nil, rateName: nil, tunneled: true, monitorName: nil,
                         display: nil, mode: nil)
    let r = try #require(report(assess([port(transports: ["CC", "CIO"], vdos: chargerCableVDOs, video: link)])[0]))
    #expect(r.video.verdict == .yes)
    #expect(r.video.certainty == .measured)
    #expect(r.video.detail.contains("Thunderbolt"))
}

@Test(arguments: [
    (4, 5.4, "4K a 60 Hz"),  // the ARZOPA link
    (2, 8.1, "4K a 60 Hz"),  // HBR3 on 2 lanes, USB 3 on the other two
    (4, 8.1, "4K a 120 Hz"),
    (4, 2.7, "2560×1440 a 60 Hz"),
    (4, 20.0, "8K a 60 Hz"),  // UHBR20, 128b/132b coding
])
func linkCapacityGivesTheLargestCommonMode(lanes: Int, gbps: Double, expected: String) {
    #expect(largestModeFitting(lanes: lanes, gbpsPerLane: gbps) == expected)
}

@Test func tooSlowALinkFitsNoCommonMode() {
    #expect(largestModeFitting(lanes: 1, gbpsPerLane: 1.62) == nil)
}

@Test func displayWithoutRefreshRateShowsOnlyTheResolution() throws {
    var link = arzopaLink
    link.mode = DisplayMode(width: 1920, height: 1080, hz: 0)  // CoreGraphics gives 0 for some panels
    let r = try #require(report(assess([port(vdos: chargerCableVDOs, video: link)])[0]))
    #expect(r.video.summary == "Sì, adesso 1920×1080")
}

// MARK: - Audio to the monitor (measured 2026-11-14: macOS lists "ARZOPA", DisplayPort, 2 output channels)

@Test func monitorAudioOnChiplessCableIsMeasured() throws {
    var link = arzopaLink
    link.audioChannels = 2
    let r = try #require(report(assess([port(transports: ["CC", "DisplayPort"], partner: arzopa, seconds: 12,
                                             video: link)])[0]))
    #expect(r.audio.verdict == .yes)
    #expect(r.audio.certainty == .measured)
    #expect(r.audio.summary == "Sì, il monitor riceve l'audio (2 canali)")
    #expect(r.audio.detail.contains("ARZOPA"))
    #expect(!r.audio.detail.contains("USB"))  // without a chip or USB 2.0 seen, USB audio is not known
}

@Test func monitorAudioBeatsWhatTheChipDeclares() throws {
    var link = arzopaLink
    link.audioChannels = 1
    let r = try #require(report(assess([port(transports: ["CC", "DisplayPort"], vdos: chargerCableVDOs,
                                             video: link)])[0]))
    #expect(r.audio.certainty == .measured)
    #expect(r.audio.summary == "Sì, il monitor riceve l'audio (1 canale)")
    // every chip cable has the USB 2.0 wires, but here they are declared, not seen working
    #expect(r.audio.detail.contains("Cuffie e schede audio USB: dichiarate dal cavo."))
}

@Test func monitorAudioWithUSB2SeenSaysUSBAudioWorks() throws {
    var link = arzopaLink
    link.audioChannels = 2
    let r = try #require(report(assess([port(transports: ["CC", "USB2", "DisplayPort"], vdos: chargerCableVDOs,
                                             video: link)])[0]))
    #expect(r.audio.detail.hasSuffix(" Vanno anche cuffie e schede audio USB."))
}

@Test func monitorWithoutAudioKeepsTheUsualAnswer() throws {
    let r = try #require(report(assess([port(transports: ["CC", "DisplayPort"], partner: arzopa, seconds: 12,
                                             video: arzopaLink)])[0]))
    #expect(r.audio.summary == "Probabilmente sì")
    #expect(r.audio.certainty == .inferred)
}

// MARK: - Power flowing now (measured 2026-11-14: 100 W charger, battery at 67% and charging)

let realPowerIn = PowerIn(milliwatts: 82_305, millivolts: 19_111, milliamps: 4_306)

@Test func chargerContractIsWhatItOffersNotWhatFlows() throws {
    let r = try #require(report(assess([port(vdos: chargerCableVDOs, partner: applePowerBrick, milliwatts: 100_000)])[0]))
    #expect(r.charging.detail == "Il caricatore offre fino a 100 W.")
}

@Test func measuredPowerIsShownWithVoltsAndAmps() throws {
    let r = try #require(report(assess([port(vdos: chargerCableVDOs, partner: applePowerBrick, milliwatts: 100_000,
                                             powerIn: realPowerIn)])[0]))
    // what flows now comes first: "240 W" alone read as if 240 W were flowing (user, 2026-11-14)
    #expect(r.charging.summary == "Adesso 82 W · il cavo regge fino a 240 W")
    #expect(r.charging.certainty == .measured)
    #expect(r.charging.detail ==
        "Misurati dal Mac: 19,1 V × 4,3 A; il caricatore ne offre fino a 100 W. Il massimo è quello dichiarato dal cavo.")
}

@Test func measuredPowerOnAChiplessCableKeepsThe60WLimit() throws {
    let r = try #require(report(assess([port(partner: applePowerBrick, milliwatts: 60_000, seconds: 12,
                                             powerIn: realPowerIn)])[0]))
    #expect(r.charging.summary == "Adesso 82 W")  // the 60 W limit is a rule, not something measured
    #expect(r.charging.detail.hasPrefix("Misurati dal Mac: 19,1 V × 4,3 A"))
    #expect(r.charging.detail.contains("3 A, cioè 60 W"))
}

@Test func loopbackIgnoresMeasuredPower() throws {
    let states = assess([
        port("Port-USB-C@1", transports: ["CC", "USB2"], vdos: chargerCableVDOs, partner: thisMac, milliwatts: 15_000,
             powerIn: realPowerIn),
        port("Port-USB-C@2", transports: ["CC", "USB2"], partner: thisMac),
    ])
    let r = try #require(report(states[0]))
    #expect(!r.charging.detail.contains("82 W"))
    #expect(!r.charging.summary.contains("82 W"))
}
