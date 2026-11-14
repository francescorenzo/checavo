import Testing
@testable import CableCore

let measured43W = PowerIn(milliwatts: 43_913, millivolts: 19_332, milliamps: 2_271)

@Test func noPowerGivesAnIdleDial() {
    let idle = PowerGauge(watts: 0, scaleMax: 100, offeredWatts: nil, port: nil)
    #expect(powerGauge([]) == idle)
    #expect(powerGauge([port(connected: false)]) == idle)
}

@Test func cableWithoutChipEndsTheDialAt60W() {
    // the iPad cable on the 60 W charger, as measured on 2026-11-14
    let g = powerGauge([port(milliwatts: 60_000, powerIn: measured43W), port("Port-USB-C@2", connected: false)])
    #expect(g == PowerGauge(watts: 43.913, scaleMax: 60, offeredWatts: 60, port: "Port-USB-C@1"))
}

@Test func chipCableEndsTheDialAtWhatItCarries() {
    let g = powerGauge([port(vdos: chargerCableVDOs, partner: applePowerBrick, milliwatts: 100_000,
                             powerIn: PowerIn(milliwatts: 70_000, millivolts: 20_000, milliamps: 3_500))])
    #expect(g == PowerGauge(watts: 70, scaleMax: 240, offeredWatts: 100, port: "Port-USB-C@1"))
}

@Test func dialGrowsWhenThePowerIsHigherThanExpected() {
    let g = powerGauge([port(powerIn: PowerIn(milliwatts: 65_000, millivolts: 20_000, milliamps: 3_250))])
    #expect(g.scaleMax == 100)
    #expect(g.watts == 65)
}

@Test func chargerOfferShowsBeforeTheMacMeasures() {
    // the battery data refreshes every 10-15 s: until then the needle stays at 0
    let g = powerGauge([port(milliwatts: 60_000)])
    #expect(g == PowerGauge(watts: 0, scaleMax: 60, offeredWatts: 60, port: "Port-USB-C@1"))
}
