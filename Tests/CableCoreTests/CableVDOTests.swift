import Foundation
import Testing
@testable import CableCore

/// A real reading saved in fixtures/ (shared with the future Windows version).
struct CableFixture: Decodable {
    struct Expected: Decodable {
        let tipo: String
        let vendorID: Int
        let productID: Int
        let velocita: String
        let ampere: Int
        let volt: Int
        let epr: Bool
        let latenza: Int
    }
    let nome: String
    let sopPrimeVDOs: [String]
    let atteso: Expected

    static func load(_ name: String) throws -> CableFixture {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/\(name).json")
        return try JSONDecoder().decode(CableFixture.self, from: Data(contentsOf: url))
    }

    /// The VDOs as ioreg shows them: bytes in memory order.
    var vdoData: [Data] { sopPrimeVDOs.map(hexData) }
}

func hexData(_ hex: String) -> Data {
    var bytes: [UInt8] = []
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        bytes.append(UInt8(hex[index..<next], radix: 16)!)
        index = next
    }
    return Data(bytes)
}

@Test func realChargerCableDecodesAsDeclared() throws {
    let fixture = try CableFixture.load("cavo-240w-usb2")
    let words = try #require(CableInfo.vdoWords(fixture.vdoData))
    #expect(words == [0x18602B01, 0x000009E2, 0x40516910, 0x000A4640])

    let cable = try #require(CableInfo.decode(vdos: words))
    #expect(cable.kind == .passive)
    #expect(Int(cable.vendorID) == fixture.atteso.vendorID)
    #expect(Int(cable.productID) == fixture.atteso.productID)
    #expect(cable.speed == .usb2)
    #expect(cable.currentAmps == fixture.atteso.ampere)
    #expect(cable.maxVolts == fixture.atteso.volt)
    #expect(cable.epr == fixture.atteso.epr)
    #expect(cable.latencyCode == fixture.atteso.latenza)
    #expect(cable.active == nil)
}

@Test func vdoOfWrongSizeIsRejected() {
    #expect(CableInfo.vdoWords([Data([0x01, 0x2B, 0x60])]) == nil)
}

@Test func tooFewVDOsGiveNoCable() {
    #expect(CableInfo.decode(vdos: []) == nil)
    #expect(CableInfo.decode(vdos: [0x18602B01, 0, 0]) == nil)  // no Cable VDO
}

@Test func unknownProductTypeIsKeptNotGuessed() throws {
    let header: UInt32 = (7 << 27) | 0x2B01
    let cable = try #require(CableInfo.decode(vdos: [header, 0, 0, 0x000A4640]))
    #expect(cable.kind == .other(7))
}

@Test func unknownSpeedAndCurrentCodesBecomeNil() throws {
    // speed 7 and current 3 are reserved in the spec
    let cable = try #require(CableInfo.decode(vdos: [0x18602B01, 0, 0, 7 | (3 << 5)]))
    #expect(cable.speed == nil)
    #expect(cable.currentAmps == nil)
}

@Test func defaultCurrentCodeMeansThreeAmps() throws {
    // code 0 = "USB Type-C default current" = 3 A for a cable
    let cable = try #require(CableInfo.decode(vdos: [0x18602B01, 0, 0, 0]))
    #expect(cable.currentAmps == 3)
}

@Test func activeOpticalUSB4CableIsDecoded() throws {
    let header: UInt32 = (4 << 27) | 0x8087
    let vdo1: UInt32 = 3 | (2 << 5) | (3 << 11) | (1 << 13) | (2 << 18)
    // VDO2: bit 10 optical, bit 9 retimer, bit 8 = 0 (USB4 supported), bit 3 two lanes
    let vdo2: UInt32 = (1 << 10) | (1 << 9) | (1 << 3)
    let cable = try #require(CableInfo.decode(vdos: [header, 0, 0x1234_0100, vdo1, vdo2]))
    #expect(cable.kind == .active)
    #expect(cable.speed == .gen3)
    #expect(cable.currentAmps == 5)
    #expect(cable.maxVolts == 20)
    let extras = try #require(cable.active)
    #expect(extras.optical)
    #expect(extras.usb4)
    #expect(extras.retimer)
    #expect(extras.twoLanes)
}

@Test func activeCableWithoutSecondVDOHasNoExtras() throws {
    let header: UInt32 = (4 << 27) | 0x8087
    let cable = try #require(CableInfo.decode(vdos: [header, 0, 0, 3]))
    #expect(cable.kind == .active)
    #expect(cable.active == nil)
}
