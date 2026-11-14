import AppKit
import CableCore
import PortReader
import SwiftUI

// Only system (semantic) colors and materials: the window follows light and dark mode by itself.

struct ContentView: View {
    let model: PortsModel

    var body: some View {
        // Three columns that never grow with the number of ports: no scrolling, everything in view.
        // The centre explains one port, the one picked on the left (or the most interesting).
        let focus = focusedPort(model.ports, model.states, picked: model.picked)
        HStack(alignment: .top, spacing: 16) {
            Sidebar(model: model, focus: focus).frame(width: 220)
            Group {
                if let focus {
                    PortCard(port: model.ports[focus], state: model.states[focus], model: model)
                } else if model.ports.isEmpty {
                    Hint(text: "Su questo Mac non trovo porte USB-C leggibili: per ora l'app funziona solo sui Mac con chip Apple.").panel()
                } else {
                    Hint(text: "Infila il cavo in una porta USB-C e collega l'altro capo a **un'altra porta USB-C di questo Mac**. Va bene anche un caricatore o un dispositivo.").panel()
                }
            }
            VStack(spacing: 8) {
                Text("Potenza in entrata").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                WattGauge(gauge: powerGauge(model.ports))
            }
            .panel(alignment: .center)
            .frame(width: 210)
        }
        .padding(20)
        .frame(width: 1000)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.default, value: model.states)
        .navigationSubtitle(model.ports.count == 1 ? "1 porta USB-C" : "\(model.ports.count) porte USB-C")
        .toolbar {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.rawData, forType: .string)
            } label: {
                Label("Copia dati grezzi", systemImage: "doc.on.doc")
            }
            .help("Copia negli appunti tutto quello che il Mac legge dalle porte, per chi vuole controllare")
        }
    }
}

/// The left column: the plug, what is going on, and the Mac's ports to pick from.
struct Sidebar: View {
    let model: PortsModel
    let focus: Int?

    var body: some View {
        // the plug and the title describe the port shown in the centre
        let plug = PlugState(focus.map { [model.states[$0]] } ?? [])
        VStack(alignment: .leading, spacing: 14) {
            PlugArt(state: plug).frame(width: 56, height: 56)
            Text(title(plug)).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            PortGrid(ports: model.ports, states: model.states, focus: focus) { model.picked = $0 }
            Spacer(minLength: 0)
            if !model.ports.isEmpty { DotLegend() }
        }
        .panel()
    }

    private func title(_ plug: PlugState) -> String {
        if model.ports.isEmpty { return "Nessuna porta USB-C leggibile" }
        switch plug {
        case .found: return "Cavo letto"
        case .reading: return "Sto leggendo il cavo…"
        case .freeEnd: return "Collega anche l'altro capo"
        case .idle: return "Collega un cavo"
        }
    }
}

extension View {
    /// The rounded box of each column; all three stretch to the height of the tallest.
    func panel(alignment: Alignment = .topLeading) -> some View {
        padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }
}

struct Hint: View {
    let text: LocalizedStringKey

    var body: some View {
        Label { Text(text) } icon: { Image(systemName: "lightbulb").foregroundStyle(.tint) }
            .font(.body).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

/// "Port-USB-C@2" → "Porta 2"
func friendlyName(_ name: String) -> String {
    name.split(separator: "@").last.map { "Porta \($0)" } ?? name
}

struct PortCard: View {
    let port: PortObservation
    let state: PortState
    let model: PortsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(friendlyName(port.name)).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                if case .report(let r) = state, r.isLoopback {
                    Text("prova tra due porte")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(.fill.tertiary, in: Capsule())
                }
            }
            switch state {
            case .reading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Sto leggendo il chip del cavo…")
                }
            case .cableOnlyFreeEnd:
                Label {
                    Text("Cavo inserito, ma l'altro capo è libero: così il Mac non può leggerlo. Collega l'altro capo a un'altra porta USB-C di questo Mac.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            case .report(let report):
                ReportView(report: report, port: port, model: model)
            case .empty, .loopbackOtherEnd:
                EmptyView()
            }
        }
        .panel()
    }
}

struct ReportView: View {
    let report: CableReport
    let port: PortObservation
    let model: PortsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(report.headline).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 2), spacing: 10) {
                AnswerTile(title: "Ricarica", icon: "bolt.fill", answer: report.charging)
                AnswerTile(title: "Video", icon: "display", answer: report.video)
                AnswerTile(title: "Audio", icon: "speaker.wave.2.fill", answer: report.audio)
                AnswerTile(title: "Dati", icon: "arrow.left.arrow.right", answer: report.data)
            }
            ForEach(report.notes, id: \.self) { note in
                Label(note, systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // a plain button rather than DisclosureGroup: that one opens only on its small arrow
            Button { model.showDetails.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.caption.weight(.bold))
                        .rotationEffect(.degrees(model.showDetails ? 90 : 0))
                    Text("Dettagli tecnici")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(.callout).foregroundStyle(.secondary)
            .accessibilityValue(model.showDetails ? "aperti" : "chiusi")
            if model.showDetails {
                Text(details).font(.caption.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var details: String {
        var lines: [String] = []
        if case .declared(let c) = report.chip {
            lines.append("Produttore (Vendor ID): \(String(format: "0x%04X", c.vendorID))\(vendorName(c.vendorID).map { " – \($0)" } ?? "")")
            lines.append("Product ID: \(String(format: "0x%04X", c.productID)) · versione \(String(format: "0x%04X", c.bcdDevice))")
            lines.append("Tipo: " + (c.kind == .active ? "attivo" : c.kind == .passive ? "passivo" : "altro"))
        }
        if let vdos = port.cableVDOs { lines.append("VDO: " + vdos.map(hexBytes).joined(separator: " ")) }
        lines.append("Collegamenti attivi: " + port.transports.joined(separator: ", "))
        return lines.joined(separator: "\n")
    }
}

struct AnswerTile: View {
    let title: String
    let icon: String
    let answer: Answer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: icon).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: answer.verdict.icon)
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, answer.verdict.color)
            }
            Text(answer.summary).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Text(answer.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(answer.certainty.label)
                .font(.caption.weight(.medium)).foregroundStyle(answer.certainty.tint)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(answer.certainty.tint.opacity(0.15), in: Capsule())
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

extension Verdict {
    var icon: String {
        switch self {
        case .yes: "checkmark.circle.fill"
        case .partial: "exclamationmark.triangle.fill"
        case .no: "xmark.circle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .yes: .green
        case .partial: .orange
        case .no: .red
        case .unknown: .secondary
        }
    }
}
