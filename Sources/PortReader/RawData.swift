import CableCore
import Foundation

/// A VDO in memory byte order, as ioreg and the fixtures show it.
public func hexBytes(_ word: UInt32) -> String {
    (0..<4).map { String(format: "%02x", (word >> (8 * $0)) & 0xFF) }.joined()
}

/// Raw readings as JSON: for "Copia dati grezzi" and for new fixtures.
public func rawJSON(_ ports: [PortObservation]) -> String {
    let items: [[String: Any]] = ports.map { p in
        var item: [String: Any] = ["porta": p.name, "collegata": p.connected, "trasporti": p.transports,
                                   "secondiDalCollegamento": Int(p.secondsSinceConnect)]
        if let v = p.cableVDOs { item["sopPrimeVDOs"] = v.map(hexBytes) }
        if let partner = p.partner {
            item["partner"] = ["vendorID": partner.vendorID, "productID": partner.productID, "computer": partner.isUSBHost]
        }
        if let mw = p.negotiatedMilliwatts { item["milliwatt"] = mw }
        if let w = p.powerIn { item["misurato"] = ["mW": w.milliwatts, "mV": w.millivolts, "mA": w.milliamps] }
        if let v = p.video {
            var video: [String: Any] = ["linee": v.lanes, "tunnel": v.tunneled]
            video["gbpsPerLinea"] = v.gbpsPerLane
            video["velocita"] = v.rateName
            video["monitor"] = v.monitorName
            video["audioCanali"] = v.audioChannels
            if let m = v.mode { video["modo"] = "\(m.width)x\(m.height)@\(m.hz)" }
            item["video"] = video
        }
        return item
    }
    guard let data = try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys]) else { return "[]" }
    return String(decoding: data, as: UTF8.self)
}
