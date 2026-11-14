import Foundation

/// What a USB-C cable's e-marker chip declares on SOP' (USB PD 3.x Discover Identity).
/// Bit layouts: USB PD r3.2 §6.4.4.3.1 (cross-checked with Linux include/linux/usb/pd_vdo.h).
public enum CableKind: Equatable, Sendable {
    case passive, active, vconnDevice
    case other(Int)
}

public enum CableSpeed: Int, Sendable, Comparable {
    case usb2 = 0, gen1, gen2, gen3, gen4  // gen4 (80 Gb/s) is new in PD r3.2

    public static func < (a: CableSpeed, b: CableSpeed) -> Bool { a.rawValue < b.rawValue }
}

public struct ActiveCableExtras: Equatable, Sendable {
    public let optical: Bool
    public let usb4: Bool
    public let retimer: Bool
    public let twoLanes: Bool
}

public struct CableInfo: Equatable, Sendable {
    public let kind: CableKind
    public let vendorID: UInt16
    public let productID: UInt16
    public let bcdDevice: UInt16
    /// nil = reserved code, not guessed
    public let speed: CableSpeed?
    public let currentAmps: Int?
    public let maxVolts: Int?
    public let epr: Bool
    /// 1 ≈ <1 m … 7 ≈ 7 m, 8 = longer/optical; 0 = not declared
    public let latencyCode: Int
    public let active: ActiveCableExtras?

    /// ioreg gives each VDO as 4 bytes in little-endian order; nil if any is malformed.
    public static func vdoWords(_ data: [Data]) -> [UInt32]? {
        var words: [UInt32] = []
        for item in data {
            guard item.count == 4 else { return nil }
            let b = [UInt8](item)
            words.append(UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24)
        }
        return words
    }

    /// VDO order: ID Header, Cert Stat, Product, Cable VDO 1, (Active Cable VDO 2).
    public static func decode(vdos: [UInt32]) -> CableInfo? {
        guard vdos.count >= 4 else { return nil }
        let header = vdos[0], product = vdos[2], cable = vdos[3]
        func bits(_ v: UInt32, _ hi: Int, _ lo: Int) -> Int { Int((v >> UInt32(lo)) & ((1 << UInt32(hi - lo + 1)) - 1)) }

        let kind: CableKind
        switch bits(header, 29, 27) {
        case 3: kind = .passive
        case 4: kind = .active
        case 6: kind = .vconnDevice
        case let other: kind = .other(other)
        }

        let current: Int? = switch bits(cable, 6, 5) {
        case 0, 1: 3  // 0 = "default"/reserved: every Type-C cable must carry at least 3 A
        case 2: 5
        default: nil
        }
        let volts: Int? = [20, 30, 40, 50][bits(cable, 10, 9)]

        var extras: ActiveCableExtras?
        if kind == .active, vdos.count >= 5 {
            let v2 = vdos[4]
            extras = ActiveCableExtras(
                optical: bits(v2, 10, 10) == 1,
                usb4: bits(v2, 8, 8) == 0,  // 0 = supported
                retimer: bits(v2, 9, 9) == 1,
                twoLanes: bits(v2, 3, 3) == 1)
        }

        return CableInfo(
            kind: kind,
            vendorID: UInt16(header & 0xFFFF),
            productID: UInt16(product >> 16),
            bcdDevice: UInt16(product & 0xFFFF),
            speed: CableSpeed(rawValue: bits(cable, 2, 0)),
            currentAmps: current,
            maxVolts: volts,
            epr: bits(cable, 17, 17) == 1,
            latencyCode: bits(cable, 16, 13),
            active: extras)
    }
}
