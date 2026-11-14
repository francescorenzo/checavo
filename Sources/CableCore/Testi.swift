/// Every user-facing sentence, in one place.
// shortcut: plain Italian strings, not localized; move to String Catalogs when English or Windows arrives.
enum Testi {
    static let declaredByChip = "Dichiarato dal chip del cavo."
    static let chipCanLie = "Questi dati sono quelli che il cavo dichiara: un cavo contraffatto può mentire."
    static let unplugAfterTest = "Prova finita? Stacca il cavo: una porta del Mac sta alimentando l'altra."

    // Headline
    static func headline(_ c: CableInfo, watts: Int?) -> String {
        var parts: [String] = []
        parts.append(watts.map { "Cavo che regge \($0) W" } ?? "Cavo")
        parts.append(c.speed.map(speedShort) ?? "velocità non dichiarata")
        if let length = length(c.latencyCode) { parts.append(length) }
        if c.kind == .active { parts.append(c.active?.optical == true ? "attivo, ottico" : "attivo") }
        return parts.joined(separator: ", ")
    }
    static let noChipHeadline = "Cavo senza chip di identificazione"
    static let unreadableHeadline = "Dati del cavo non leggibili"
    static let unreadableDetail = "Il cavo ha risposto, ma con dati che non riesco a interpretare. Usa «Copia dati grezzi» per segnalarlo."

    static func speedShort(_ s: CableSpeed) -> String {
        switch s {
        case .usb2: "solo USB 2.0"
        case .gen1: "USB 5 Gbit/s"
        case .gen2: "USB 10 Gbit/s"
        case .gen3: "USB4/Thunderbolt 40 Gbit/s"
        case .gen4: "USB4 80 Gbit/s"
        }
    }

    static func length(_ latency: Int) -> String? {
        switch latency {
        case 1: "lungo meno di 1 m"
        case 2...7: "lungo circa \(latency - 1)–\(latency) m"
        case 8: "lungo oltre 7 m"
        default: nil
        }
    }

    // Charging
    static func upToWatts(_ w: Int) -> String { "Fino a \(w) W" }
    static func chargerOffers(watts: Int) -> String { "Il caricatore offre fino a \(watts) W." }
    static func chargingNow(_ p: PowerIn, cableWatts: Int?) -> String {
        "Adesso \(Int((Double(p.milliwatts) / 1000).rounded())) W" + (cableWatts.map { " · il cavo regge fino a \($0) W" } ?? "")
    }
    static func powerNowDetail(_ p: PowerIn, offeredMilliwatts: Int?) -> String {
        func one(_ milli: Int) -> String { String(format: "%.1f", Double(milli) / 1000).replacingOccurrences(of: ".", with: ",") }
        return "Misurati dal Mac: \(one(p.millivolts)) V × \(one(p.milliamps)) A"
            + (offeredMilliwatts.map { "; il caricatore ne offre fino a \($0 / 1000) W" } ?? "") + "."
    }
    static let maxFromCable = "Il massimo è quello dichiarato dal cavo."
    static let chargingLoopback = "Nella prova tra due porte passano pochi watt: è normale. Il massimo è quello dichiarato dal cavo."
    static let unknownWatts = "Potenza non dichiarata"
    static let noChipCharging = "Senza chip un cavo USB-C vale al massimo 3 A, cioè 60 W."

    // Video
    static let noVideo = "Non porta il video"
    static let noVideoDetail = "Il cavo è solo USB 2.0: mancano i fili veloci che servono al video. Eccezione: monitor e adattatori DisplayLink."
    static func videoLimit(_ s: CableSpeed) -> String {
        switch s {
        case .usb2: noVideo
        case .gen1: "Fino a 4K a 60 Hz"
        case .gen2: "Fino a 4K a 120 Hz o 5K a 60 Hz"
        case .gen3: "Fino a 6K a 60 Hz (8K con compressione)"
        case .gen4: "Fino a 8K a 60 Hz"
        }
    }
    static let videoDependsOnMac = "Limite del cavo, ricavato dalla sua velocità. Contano anche il Mac e il monitor; se sullo stesso cavo passano anche dati USB 3, la risoluzione può scendere."
    static let videoActiveNow = "Limite del cavo, ricavato dalla sua velocità. Adesso un collegamento video è attivo."
    static let videoTryMonitor = "Da provare con un monitor"
    static let noChipVideo = "Senza chip il cavo non dice se ha i fili per il video. Collegalo a un monitor: l'app misura il video che passa."
    static func videoNow(_ mode: DisplayMode?) -> String {
        guard let m = mode else { return "Sì, il video passa adesso" }
        let hz = Int(m.hz.rounded())
        return "Sì, adesso \(m.width)×\(m.height)" + (hz > 0 ? " a \(hz) Hz" : "")
    }
    static func videoNowDetail(_ link: VideoLink, fits: String?) -> String {
        var parts = ["Provato adesso" + (link.monitorName.map { " con il monitor \($0)" } ?? "") + "."]
        if link.tunneled {
            parts.append("Il video passa dentro Thunderbolt/USB4.")
        } else {
            let rate = link.gbpsPerLane.map { " a \(String(format: "%g", $0).replacingOccurrences(of: ".", with: ",")) Gbit/s" } ?? ""
            let name = link.rateName.map { " (\($0))" } ?? ""
            parts.append("DisplayPort su \(link.lanes) \(link.lanes == 1 ? "linea" : "linee")\(rate)\(name).")
        }
        if let fits {
            parts.append("Senza compressione questo collegamento basta fino a \(fits); con un monitor più esigente il cavo potrebbe dare di più.")
        }
        return parts.joined(separator: " ")
    }
    static let unknownSpeed = "Velocità non dichiarata"

    // Audio
    static let audioYes = "Sì, cuffie e schede audio USB"
    static let audioDeclared = "L'audio USB usa i fili USB 2.0, che ogni cavo con chip deve avere."
    static let audioNo = "No"
    static let audioProbably = "Probabilmente sì"
    static func audioNow(channels: Int) -> String {
        "Sì, il monitor riceve l'audio (\(channels) \(channels == 1 ? "canale" : "canali"))"
    }
    /// The USB audio sentence says how it is known: seen working, or only declared by the chip.
    static func audioNowDetail(_ link: VideoLink, usbAudio: Certainty?) -> String {
        let usb = switch usbAudio {
        case .measured: " Vanno anche cuffie e schede audio USB."
        case .declared: " Cuffie e schede audio USB: dichiarate dal cavo."
        default: ""
        }
        return "Provato adesso: il Mac manda l'audio" + (link.monitorName.map { " al monitor \($0)" } ?? " al monitor")
            + " attraverso questo cavo, insieme al video." + usb
    }

    // Data
    static func dataSpeed(_ s: CableSpeed) -> String {
        switch s {
        case .usb2: "Lenti: 480 Mbit/s (10 GB in circa 5 minuti)"
        case .gen1: "5 Gbit/s (10 GB in circa 30 secondi)"
        case .gen2: "10 Gbit/s (10 GB in circa 15 secondi)"
        case .gen3: "40 Gbit/s (10 GB in circa 5 secondi)"
        case .gen4: "80 Gbit/s (10 GB in circa 3 secondi)"
        }
    }
    static let usb2Measured = "Provato adesso: i fili dati USB 2.0 funzionano."
    static let dataNo = "No, nessun collegamento dati"
    static let chargeOnly = "Provato adesso: tra le due porte non passa nessun dato. È un cavo solo ricarica."
    static let dataAtLeastUSB2 = "Almeno USB 2.0 (480 Mbit/s)"
    static let fastWiresSeen = "Ha i fili veloci; velocità non dichiarata"
    static let fastWiresSeenDetail = "Il video li sta usando adesso, quindi ci sono. Senza chip non si sa a che velocità reggono i dati."
    static let tryLoopback = "Per saperlo con certezza collega il cavo tra due porte USB-C di questo Mac."
}

extension Certainty {
    public var label: String {
        switch self {
        case .declared: "dichiarato dal cavo"
        case .measured: "provato adesso"
        case .inferred: "dedotto"
        case .unknowable: "non si può sapere"
        }
    }
}

extension Verdict {
    public var symbol: String {
        switch self {
        case .yes: "✅"
        case .partial: "⚠️"
        case .no: "❌"
        case .unknown: "❔"
        }
    }
}

/// Only names we are sure of; "unknown" is a normal answer.
public func vendorName(_ id: UInt16) -> String? {
    [0x05AC: "Apple", 0x8087: "Intel", 0x04E8: "Samsung", 0x18D1: "Google", 0x050D: "Belkin"][id]
}
