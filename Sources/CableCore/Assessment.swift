/// Turns what the Mac sees on each USB-C port into the four practical answers
/// (charging, video, audio, data), each with how sure we are.

public struct Partner: Equatable, Sendable {
    public let vendorID: Int
    public let productID: Int
    /// ID Header bit 31: the device at the other end is a USB host (a computer).
    public let isUSBHost: Bool

    public init(vendorID: Int, productID: Int, isUSBHost: Bool) {
        self.vendorID = vendorID
        self.productID = productID
        self.isUSBHost = isUSBHost
    }
}

/// Power entering the Mac now, measured by the Mac itself (SMC DC-in sensors).
public struct PowerIn: Equatable, Sendable {
    public let milliwatts: Int
    public let millivolts: Int
    public let milliamps: Int

    public init(milliwatts: Int, millivolts: Int, milliamps: Int) {
        self.milliwatts = milliwatts
        self.millivolts = millivolts
        self.milliamps = milliamps
    }
}

public struct PortObservation: Equatable, Sendable {
    public var name: String
    public var connected: Bool
    /// TransportsActive, e.g. ["CC", "USB2", "USB3", "CIO", "DisplayPort"]
    public var transports: [String]
    /// SOP' Discover Identity VDOs (the cable's chip); nil = chip not seen
    public var cableVDOs: [UInt32]?
    /// SOP Discover Identity of the device at the other end
    public var partner: Partner?
    public var negotiatedMilliwatts: Int?
    public var secondsSinceConnect: Double
    /// Active DisplayPort link: video measured now
    public var video: VideoLink?
    /// Power flowing into the Mac through this port now
    public var powerIn: PowerIn?

    public init(name: String, connected: Bool, transports: [String], cableVDOs: [UInt32]?,
                partner: Partner?, negotiatedMilliwatts: Int?, secondsSinceConnect: Double,
                video: VideoLink? = nil) {
        self.name = name
        self.connected = connected
        self.transports = transports
        self.cableVDOs = cableVDOs
        self.partner = partner
        self.negotiatedMilliwatts = negotiatedMilliwatts
        self.secondsSinceConnect = secondsSinceConnect
        self.video = video
    }
}

public enum Certainty: Sendable { case declared, measured, inferred, unknowable }
public enum Verdict: Sendable { case yes, partial, no, unknown }

public struct Answer: Equatable, Sendable {
    public let verdict: Verdict
    public let summary: String
    public let detail: String
    public let certainty: Certainty
}

public enum ChipStatus: Equatable, Sendable {
    case declared(CableInfo)
    case absent
    case unreadable
}

public struct CableReport: Equatable, Sendable {
    public let headline: String
    public let chip: ChipStatus
    public let charging, video, audio, data: Answer
    public let isLoopback: Bool
    public let notes: [String]
}

public enum PortState: Equatable, Sendable {
    case empty
    case reading
    case cableOnlyFreeEnd
    /// This port holds the other end of a cable being tested on the named port.
    case loopbackOtherEnd(String)
    case report(CableReport)
}

/// The chip answered ~5 s after plugging on the real Mac: wait this long before saying "no chip".
public let chipTimeoutSeconds = 10.0
/// Power and partner show up within ~1 s; after this a lone "CC" means a cable with a free end.
public let freeEndAfterSeconds = 3.0

public func assess(_ ports: [PortObservation]) -> [PortState] {
    let loop = loopbackPorts(ports)
    return ports.indices.map { i in
        let p = ports[i]
        guard p.connected else { return .empty }
        if let loop, loop.contains(i) {
            let tested = loop.first { ports[$0].cableVDOs != nil } ?? loop[0]
            if i != tested { return .loopbackOtherEnd(ports[tested].name) }
            let usb2 = loop.contains { ports[$0].transports.contains("USB2") }
            return reportOrWait(p, loopback: true, loopHasUSB2: usb2)
        }
        return reportOrWait(p, loopback: false, loopHasUSB2: false)
    }
}

/// Two or more connected ports that see the same computer at the other end: this Mac, through one cable.
private func loopbackPorts(_ ports: [PortObservation]) -> [Int]? {
    for i in ports.indices {
        guard ports[i].connected, let partner = ports[i].partner, partner.isUSBHost else { continue }
        let same = ports.indices.filter { ports[$0].connected && ports[$0].partner == partner }
        if same.count >= 2 { return same }
    }
    return nil
}

private func reportOrWait(_ p: PortObservation, loopback: Bool, loopHasUSB2: Bool) -> PortState {
    if let vdos = p.cableVDOs {
        guard let cable = CableInfo.decode(vdos: vdos) else {
            return .report(unreadableReport(loopback: loopback))
        }
        return .report(chipReport(cable, p, loopback: loopback, loopHasUSB2: loopHasUSB2))
    }
    let somethingAttached = loopback || p.partner != nil || p.negotiatedMilliwatts != nil
        || p.transports.contains { $0 != "CC" }
    if !somethingAttached {
        return p.secondsSinceConnect < freeEndAfterSeconds ? .reading : .cableOnlyFreeEnd
    }
    if p.secondsSinceConnect < chipTimeoutSeconds { return .reading }
    return .report(noChipReport(p, loopback: loopback, loopHasUSB2: loopHasUSB2))
}

// MARK: - Reports

private func chipReport(_ c: CableInfo, _ p: PortObservation, loopback: Bool, loopHasUSB2: Bool) -> CableReport {
    let watts = maxWatts(c)
    let chargingDetail: String
    if loopback {
        chargingDetail = Testi.chargingLoopback
    } else if let mw = p.negotiatedMilliwatts {
        chargingDetail = Testi.chargerOffers(watts: mw / 1000)
    } else {
        chargingDetail = Testi.declaredByChip
    }
    let charging = (loopback ? nil : p.powerIn).map {
        measuredCharging($0, p, cableWatts: watts, limit: watts == nil ? nil : Testi.maxFromCable)
    }
        ?? watts.map { Answer(verdict: .yes, summary: Testi.upToWatts($0), detail: chargingDetail, certainty: .declared) }
        ?? Answer(verdict: .unknown, summary: Testi.unknownWatts, detail: Testi.declaredByChip, certainty: .unknowable)

    let video: Answer
    switch (p.video, c.speed) {
    case (.some(let link), _): video = measuredVideo(link)  // what passes now beats what the chip declares
    case (nil, .usb2): video = Answer(verdict: .no, summary: Testi.noVideo, detail: Testi.noVideoDetail, certainty: .declared)
    case (nil, .some(let s)): video = Answer(verdict: .yes, summary: Testi.videoLimit(s), detail: videoDetail(p), certainty: .inferred)
    case (nil, nil): video = Answer(verdict: .unknown, summary: Testi.unknownSpeed, detail: Testi.declaredByChip, certainty: .unknowable)
    }

    let measuredUSB2 = loopback ? loopHasUSB2 : p.transports.contains("USB2")
    // every chip cable has the USB 2.0 wires: declared, or seen working
    let audio = p.video.flatMap { monitorAudio($0, usbAudio: measuredUSB2 ? .measured : .declared) }
        ?? Answer(verdict: .yes, summary: Testi.audioYes,
                  detail: measuredUSB2 ? Testi.usb2Measured : Testi.audioDeclared,
                  certainty: measuredUSB2 ? .measured : .declared)

    let data: Answer
    if let s = c.speed {
        data = Answer(verdict: s == .usb2 ? .partial : .yes, summary: Testi.dataSpeed(s),
                      detail: measuredUSB2 ? Testi.usb2Measured : Testi.declaredByChip,
                      certainty: measuredUSB2 ? .measured : .declared)
    } else {
        data = Answer(verdict: .unknown, summary: Testi.unknownSpeed, detail: Testi.declaredByChip, certainty: .unknowable)
    }

    var notes = [Testi.chipCanLie]
    if loopback { notes.insert(Testi.unplugAfterTest, at: 0) }
    return CableReport(headline: Testi.headline(c, watts: watts), chip: .declared(c),
                       charging: charging, video: video, audio: audio, data: data,
                       isLoopback: loopback, notes: notes)
}

private func noChipReport(_ p: PortObservation, loopback: Bool, loopHasUSB2: Bool) -> CableReport {
    let hasUSB2 = loopback ? loopHasUSB2 : p.transports.contains("USB2")
    // the 60 W limit is a rule for chipless cables, not part of the measurement
    let charging = (loopback ? nil : p.powerIn).map { measuredCharging($0, p, cableWatts: nil, limit: Testi.noChipCharging) }
        ?? Answer(verdict: .yes, summary: Testi.upToWatts(60), detail: Testi.noChipCharging, certainty: .inferred)
    let video = p.video.map(measuredVideo)
        ?? Answer(verdict: .unknown, summary: Testi.videoTryMonitor, detail: Testi.noChipVideo, certainty: .unknowable)
    var audio: Answer
    var data: Answer
    if hasUSB2 {
        audio = Answer(verdict: .yes, summary: Testi.audioYes, detail: Testi.usb2Measured, certainty: .measured)
        data = Answer(verdict: .partial, summary: Testi.dataAtLeastUSB2, detail: Testi.usb2Measured, certainty: .measured)
    } else if loopback {
        audio = Answer(verdict: .no, summary: Testi.audioNo, detail: Testi.chargeOnly, certainty: .measured)
        data = Answer(verdict: .no, summary: Testi.dataNo, detail: Testi.chargeOnly, certainty: .measured)
    } else {
        audio = Answer(verdict: .unknown, summary: Testi.audioProbably, detail: Testi.tryLoopback, certainty: .inferred)
        data = Answer(verdict: .unknown, summary: Testi.unknownSpeed, detail: Testi.tryLoopback, certainty: .inferred)
    }
    // DisplayPort runs on the fast wire pairs: if it passes, the cable has them (deduced: no data was moved)
    if p.video != nil {
        data = Answer(verdict: .unknown, summary: Testi.fastWiresSeen, detail: Testi.fastWiresSeenDetail, certainty: .inferred)
    }
    if let a = p.video.flatMap({ monitorAudio($0, usbAudio: hasUSB2 ? .measured : nil) }) { audio = a }
    var notes: [String] = []
    if loopback { notes.append(Testi.unplugAfterTest) }
    return CableReport(headline: Testi.noChipHeadline, chip: .absent, charging: charging, video: video,
                       audio: audio, data: data, isLoopback: loopback, notes: notes)
}

private func unreadableReport(loopback: Bool) -> CableReport {
    let unknown = Answer(verdict: .unknown, summary: Testi.unreadableHeadline, detail: Testi.unreadableDetail, certainty: .unknowable)
    return CableReport(headline: Testi.unreadableHeadline, chip: .unreadable, charging: unknown, video: unknown,
                       audio: unknown, data: unknown, isLoopback: loopback, notes: [])
}

/// What flows now comes first; the cable's limit follows, so "240 W" is not read as what passes.
private func measuredCharging(_ power: PowerIn, _ p: PortObservation, cableWatts: Int?, limit: String?) -> Answer {
    Answer(verdict: .yes, summary: Testi.chargingNow(power, cableWatts: cableWatts),
           detail: Testi.powerNowDetail(power, offeredMilliwatts: p.negotiatedMilliwatts) + (limit.map { " " + $0 } ?? ""),
           certainty: .measured)
}

private func measuredVideo(_ link: VideoLink) -> Answer {
    let capacity = link.gbpsPerLane.flatMap { largestModeFitting(lanes: link.lanes, gbpsPerLane: $0) }
    return Answer(verdict: .yes, summary: Testi.videoNow(link.mode), detail: Testi.videoNowDetail(link, fits: capacity),
                  certainty: .measured)
}

/// DisplayPort carries the audio on the same wires as the video: a monitor macOS sends audio to proves it passes.
private func monitorAudio(_ link: VideoLink, usbAudio: Certainty?) -> Answer? {
    link.audioChannels.map {
        Answer(verdict: .yes, summary: Testi.audioNow(channels: $0),
               detail: Testi.audioNowDetail(link, usbAudio: usbAudio), certainty: .measured)
    }
}

private func videoDetail(_ p: PortObservation) -> String {
    p.transports.contains("DisplayPort") || p.transports.contains("CIO") ? Testi.videoActiveNow : Testi.videoDependsOnMac
}

/// 3 A → 60 W; 5 A → 100 W; 5 A + 50 V + EPR → 240 W (EPR tops out at 48 V × 5 A).
func maxWatts(_ c: CableInfo) -> Int? {
    switch c.currentAmps {
    case 3: return 60
    case 5: return (c.maxVolts ?? 20) >= 50 && c.epr ? 240 : 100
    default: return nil
    }
}
