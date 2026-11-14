// usbc-dump: shows what this Mac sees on each USB-C port and what the app would answer.
//   usbc-dump            one reading
//   usbc-dump --watch    print every change (Ctrl-C to stop)
//   usbc-dump --json     raw readings, ready to become a fixture
//   usbc-dump --bench    time of one reading
import CableCore
import Foundation
import PortReader

let args = CommandLine.arguments.dropFirst()
let monitor = PortMonitor()

func render(_ ports: [PortObservation]) -> String {
    let states = assess(ports)
    var out = ""
    for (p, state) in zip(ports, states) {
        out += "\(p.name): " + (p.connected ? "collegata" : "libera") + "\n"
        if p.connected {
            out += "  trasporti: \(p.transports.joined(separator: ", "))\n"
            if let partner = p.partner {
                out += "  all'altro capo: vendor \(partner.vendorID), product \(partner.productID)\(partner.isUSBHost ? " (computer)" : "")\n"
            }
            if let mw = p.negotiatedMilliwatts { out += "  potenza in arrivo: \(mw / 1000) W\n" }
            if let vdos = p.cableVDOs { out += "  chip del cavo (SOP'): \(vdos.map(hexBytes).joined(separator: " "))\n" }
        }
        switch state {
        case .empty: break
        case .reading: out += "  → sto leggendo il cavo…\n"
        case .cableOnlyFreeEnd: out += "  → cavo inserito con l'altro capo libero: collegalo a un'altra porta USB-C di questo Mac\n"
        case .loopbackOtherEnd(let other): out += "  → altro capo del cavo in prova su \(other)\n"
        case .report(let r):
            out += "  → \(r.headline)\(r.isLoopback ? "  [prova tra due porte]" : "")\n"
            for (title, a) in [("Ricarica", r.charging), ("Video", r.video), ("Audio", r.audio), ("Dati", r.data)] {
                out += "     \(a.verdict.symbol) \(title): \(a.summary)  [\(a.certainty.label)]\n        \(a.detail)\n"
            }
            for note in r.notes { out += "     · \(note)\n" }
        }
    }
    return out.isEmpty ? "Nessuna porta USB-C trovata: Mac non ancora supportato.\n" : out
}

if args.contains("--bench") {
    let start = Date()
    for _ in 0..<100 { _ = monitor.readNow() }
    print(String(format: "una lettura: %.2f ms", Date().timeIntervalSince(start) * 10))
} else if args.contains("--json") {
    print(rawJSON(monitor.readNow()))
} else if args.contains("--watch") {
    var last = ""
    while true {
        let text = render(monitor.readNow())
        if text != last {
            print("===== \(Date().formatted(date: .omitted, time: .standard))\n\(text)")
            last = text
        }
        Thread.sleep(forTimeInterval: 1)
    }
} else {
    // one-shot: assume ports were connected long ago, so a missing chip is reported, not waited for
    print(render(monitor.readNow().map { var p = $0; if p.connected { p.secondsSinceConnect = 60 }; return p }))
}
