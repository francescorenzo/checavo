/// Which port the window explains: the one the user picked, else the most interesting one.
/// A picked port that is empty (the cable was pulled) falls back to the most interesting.
public func focusedPort(_ ports: [PortObservation], _ states: [PortState], picked: String?) -> Int? {
    if let picked, let i = ports.firstIndex(where: { $0.name == picked }), i < states.count {
        switch states[i] {
        case .empty: break
        case .loopbackOtherEnd(let other):
            // the far end of a test between two ports: the answers live on the tested port
            if let j = ports.firstIndex(where: { $0.name == other }) { return j }
        default: return i
        }
    }
    func first(_ match: (PortState) -> Bool) -> Int? { states.firstIndex(where: match) }
    return first { if case .report = $0 { true } else { false } }
        ?? first { $0 == .reading }
        ?? first { $0 == .cableOnlyFreeEnd }
}
