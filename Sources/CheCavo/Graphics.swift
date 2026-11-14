import CableCore
import SwiftUI

// Drawings of the window. Only system colors: they follow light and dark mode by themselves.

enum PlugState {
    case idle      // nothing to say: outline plug
    case reading   // waiting for the cable's chip: dots run down the cable
    case found     // a cable was read: solid plug
    case freeEnd   // a cable with nothing at the other end: slashed plug

    /// The most interesting port wins.
    init(_ states: [PortState]) {
        if states.contains(where: { if case .report = $0 { true } else { false } }) { self = .found }
        else if states.contains(.reading) { self = .reading }
        else if states.contains(.cableOnlyFreeEnd) { self = .freeEnd }
        else { self = .idle }
    }
}

/// A stylized USB-C plug with its cable, drawn on an 18×18 grid.
struct PlugArt: View {
    let state: PlugState

    var body: some View {
        TimelineView(.animation(paused: state != .reading)) { timeline in
            Canvas { context, size in
                let phase = timeline.date.timeIntervalSinceReferenceDate * 3
                draw(&context, size: size, phase: -phase.truncatingRemainder(dividingBy: 1.8))
            }
        }
        .accessibilityHidden(true)
    }

    private var color: Color {
        switch state {
        case .idle: .secondary
        case .reading, .found: .accentColor
        case .freeEnd: .orange
        }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, phase: Double) {
        context.scaleBy(x: size.width / 18, y: size.height / 18)
        let shading = GraphicsContext.Shading.color(color)
        context.drawLayer { layer in
            let tip = Path(roundedRect: CGRect(x: 5.25, y: 1.25, width: 7.5, height: 4.5), cornerRadius: 2.25)
            layer.stroke(tip, with: shading, lineWidth: 1.5)
            layer.stroke(Path { $0.move(to: CGPoint(x: 7.5, y: 3.5)); $0.addLine(to: CGPoint(x: 10.5, y: 3.5)) },
                         with: shading, style: StrokeStyle(lineWidth: 1.25, lineCap: .round))
            let body = Path(roundedRect: CGRect(x: 4.25, y: 6.25, width: 9.5, height: 5), cornerRadius: 2)
            // a light fill keeps the grip readable as a plug when it is drawn big
            layer.fill(body, with: state == .found ? shading : .color(color.opacity(0.2)))
            layer.stroke(body, with: shading, lineWidth: 1.5)
            let cable = Path { $0.move(to: CGPoint(x: 9, y: state == .reading ? 13 : 12)); $0.addLine(to: CGPoint(x: 9, y: 17.5)) }
            let dots: [CGFloat] = state == .reading ? [0, 1.8] : []
            layer.stroke(cable, with: shading, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dots, dashPhase: phase))
            guard state == .freeEnd else { return }
            let slash = Path { $0.move(to: CGPoint(x: 2.5, y: 16.5)); $0.addLine(to: CGPoint(x: 15.5, y: 1.5)) }
            layer.blendMode = .destinationOut  // a gap around the slash
            layer.stroke(slash, with: .color(.black), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            layer.blendMode = .normal
            layer.stroke(slash, with: shading, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
    }
}

/// The Mac's USB-C ports as sockets with a status dot, two per row: 3 or 4 ports still fit.
/// Clicking a port with a cable shows it in the centre.
struct PortGrid: View {
    let ports: [PortObservation]
    let states: [PortState]
    let focus: Int?
    let pick: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
            ForEach(Array(zip(ports, states).enumerated()), id: \.element.0.name) { i, item in
                cell(item.0, item.1, selected: i == focus)
            }
        }
    }

    private func cell(_ port: PortObservation, _ state: PortState, selected: Bool) -> some View {
        Button { pick(port.name) } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary, lineWidth: 2)
                    Capsule().fill(.secondary).frame(width: 20, height: 4)
                }
                .frame(width: 44, height: 20)
                .overlay(alignment: .topTrailing) { StatusDot(state: state).offset(x: 6, y: -6) }
                .padding(.top, 6)
                Text(friendlyName(port.name)).font(.caption.weight(.medium))
                Text(status(state)).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(selected ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(state == .empty)  // nothing to show on a free port
        .help(state == .empty ? "" : "Mostra le risposte di questa porta")
        .accessibilityLabel("\(friendlyName(port.name)), \(status(state))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func status(_ state: PortState) -> String {
        switch state {
        case .empty: "libera"
        case .reading: "lettura…"
        case .cableOnlyFreeEnd: "capo libero"
        case .loopbackOtherEnd: "altro capo"
        case .report: "cavo letto"
        }
    }
}

/// What the dots on the ports mean, at the foot of the left column.
struct DotLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row(.loopbackOtherEnd(""), "cavo letto")  // same green dot as a report
            row(.reading, "lettura in corso")
            row(.cableOnlyFreeEnd, "altro capo libero")
            row(.empty, "porta libera")
        }
        .font(.caption).foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private func row(_ state: PortState, _ text: String) -> some View {
        HStack(spacing: 8) { StatusDot(state: state).frame(width: 14); Text(text) }
    }
}

private struct StatusDot: View {
    let state: PortState

    var body: some View {
        switch state {
        case .empty:
            Circle().strokeBorder(.secondary, lineWidth: 1.5).frame(width: 12, height: 12)
        case .reading:
            dot(.yellow).phaseAnimator([1.0, 0.25]) { $0.opacity($1) } animation: { _ in .easeInOut(duration: 0.7) }
        case .cableOnlyFreeEnd:
            dot(.orange)
        case .report, .loopbackOtherEnd:
            dot(.green)
        }
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color)
            .overlay(Circle().strokeBorder(Color(nsColor: .controlBackgroundColor), lineWidth: 2))
            .frame(width: 14, height: 14)
    }
}

/// A speedometer-style dial with the watts entering the Mac now.
struct WattGauge: View {
    let gauge: PowerGauge
    private let radius: CGFloat = 80
    private let sweep = 240.0  // degrees, from lower left (150°) clockwise to lower right (30°)

    private var fraction: Double { min(max(gauge.watts / Double(gauge.scaleMax), 0), 1) }

    var body: some View {
        ZStack {
            Circle().trim(from: 0, to: sweep / 360)
                .stroke(.quaternary, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(150))
            Circle().trim(from: 0, to: sweep / 360 * fraction)
                .stroke(AngularGradient(colors: [.teal, .green], center: .center, startAngle: .zero, endAngle: .degrees(sweep)),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(150))
            ticks
            if let offered = gauge.offeredWatts, offered < gauge.scaleMax {
                Capsule().fill(.primary.opacity(0.7)).frame(width: 18, height: 3)
                    .offset(x: radius)
                    .rotationEffect(.degrees(150 + sweep * Double(offered) / Double(gauge.scaleMax)))
            }
            // the needle stops short of the scale numbers
            Capsule().fill(.primary).frame(width: radius - 40, height: 4)
                .offset(x: (radius - 40) / 2)
                .rotationEffect(.degrees(150 + sweep * fraction))
            Circle().fill(.primary).frame(width: 14, height: 14)
            Circle().fill(Color(nsColor: .controlBackgroundColor)).frame(width: 5, height: 5)
            VStack(spacing: 0) {
                Text("\(Int(gauge.watts.rounded())) W")
                    .font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText(value: gauge.watts))
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
            .offset(y: radius * 0.62)
        }
        .frame(width: radius * 2 + 16, height: radius * 2 + 16)
        .frame(height: radius * 1.95, alignment: .top)  // the dial is open at the bottom: no empty space there
        .animation(.spring(duration: 0.8), value: gauge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Potenza in entrata: \(Int(gauge.watts.rounded())) watt su \(gauge.scaleMax)")
    }

    private var caption: String {
        guard gauge.port != nil else { return "nessuna ricarica" }
        guard let offered = gauge.offeredWatts else { return "in entrata adesso" }
        return "il caricatore offre \(offered) W"
    }

    private var ticks: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            func point(_ f: Double, _ r: CGFloat) -> CGPoint {
                let a = (150 + sweep * f) * .pi / 180
                return CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
            }
            for i in 0...8 {
                let f = Double(i) / 8
                let long = i % 4 == 0
                context.stroke(Path { $0.move(to: point(f, radius - 12)); $0.addLine(to: point(f, radius - (long ? 20 : 16))) },
                               with: .color(.secondary), lineWidth: long ? 1.5 : 1)
            }
            for f in [0.0, 0.5, 1.0] {
                let value = Int((Double(gauge.scaleMax) * f).rounded())
                context.draw(Text("\(value)").font(.caption2).foregroundStyle(.secondary), at: point(f, radius - 32))
            }
        }
    }
}

extension Certainty {
    var tint: Color {
        switch self {
        case .measured: .green
        case .declared: .blue
        case .inferred, .unknowable: .secondary
        }
    }
}
