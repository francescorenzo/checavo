import Testing
@testable import CableCore

private let four = ["Port-USB-C@1", "Port-USB-C@2", "Port-USB-C@3", "Port-USB-C@4"].map { port($0) }
private let someReport = PortState.report(CableReport(
    headline: "x", chip: .absent, charging: unknownAnswer, video: unknownAnswer, audio: unknownAnswer,
    data: unknownAnswer, isLoopback: false, notes: []))
private let unknownAnswer = Answer(verdict: .unknown, summary: "", detail: "", certainty: .unknowable)

@Test func nothingToShowWithoutCables() {
    #expect(focusedPort(four, [.empty, .empty, .empty, .empty], picked: nil) == nil)
}

@Test func aReadCableWinsOverOneStillReading() {
    #expect(focusedPort(four, [.reading, .empty, someReport, .empty], picked: nil) == 2)
}

@Test func thePortTheUserPickedIsShown() {
    #expect(focusedPort(four, [.reading, .empty, someReport, .empty], picked: "Port-USB-C@1") == 0)
}

@Test func anEmptyOrMissingPickFallsBackToTheMostInteresting() {
    #expect(focusedPort(four, [.cableOnlyFreeEnd, .empty, .empty, .empty], picked: "Port-USB-C@2") == 0)
    #expect(focusedPort(four, [.empty, .reading, .empty, .empty], picked: "Port-USB-C@9") == 1)
}

@Test func theFarEndOfATestShowsTheTestedPort() {
    let states: [PortState] = [someReport, .empty, .empty, .loopbackOtherEnd("Port-USB-C@1")]
    #expect(focusedPort(four, states, picked: "Port-USB-C@4") == 0)
}
