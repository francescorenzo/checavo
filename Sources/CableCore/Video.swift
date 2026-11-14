import Foundation

/// What a monitor shows right now (CoreGraphics).
public struct DisplayMode: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let hz: Double

    public init(width: Int, height: Int, hz: Double) {
        self.width = width
        self.height = height
        self.hz = hz
    }
}

/// EDID identity of a monitor, the same numbers CoreGraphics reports, so the two can be matched.
public struct DisplayID: Equatable, Sendable {
    public let vendor: UInt16
    public let product: UInt16
    public let serial: UInt32

    public init(vendor: UInt16, product: UInt16, serial: UInt32) {
        self.vendor = vendor
        self.product = product
        self.serial = serial
    }
}

/// An active DisplayPort link on a USB-C port: proof that video is going through the cable now.
public struct VideoLink: Equatable, Sendable {
    public var lanes: Int
    public var gbpsPerLane: Double?
    public var rateName: String?
    /// DisplayPort inside a Thunderbolt/USB4 link instead of DisplayPort alt mode
    public var tunneled: Bool
    public var monitorName: String?
    public var display: DisplayID?
    public var mode: DisplayMode?
    /// Output channels of the monitor's audio device in macOS; nil = no audio to this monitor
    public var audioChannels: Int?

    public init(lanes: Int, gbpsPerLane: Double?, rateName: String?, tunneled: Bool, monitorName: String?,
                display: DisplayID?, mode: DisplayMode?, audioChannels: Int? = nil) {
        self.lanes = lanes
        self.gbpsPerLane = gbpsPerLane
        self.rateName = rateName
        self.tunneled = tunneled
        self.monitorName = monitorName
        self.display = display
        self.mode = mode
        self.audioChannels = audioChannels
    }
}

/// Usable Gbit/s of a DisplayPort link: 8b/10b up to HBR3, 128b/132b from UHBR10.
func usableGbps(lanes: Int, gbpsPerLane: Double) -> Double {
    Double(lanes) * gbpsPerLane * (gbpsPerLane >= 10 ? 128.0 / 132.0 : 0.8)
}

/// Uncompressed 8-bit RGB with CVT reduced blanking v2 (80 px, 460 µs).
func requiredGbps(width: Int, height: Int, hz: Double) -> Double {
    let totalLines = Double(height) / (1 - 460e-6 * hz)
    return Double(width + 80) * totalLines * hz * 24 / 1e9
}

private let commonModes: [(name: String, width: Int, height: Int, hz: Double)] = [
    ("1080p a 60 Hz", 1920, 1080, 60),
    ("2560×1440 a 60 Hz", 2560, 1440, 60),
    ("4K a 60 Hz", 3840, 2160, 60),
    ("5K a 60 Hz", 5120, 2880, 60),
    ("4K a 120 Hz", 3840, 2160, 120),
    ("6K a 60 Hz", 6016, 3384, 60),
    ("8K a 60 Hz", 7680, 4320, 60),
]

/// The most demanding common mode this link carries without compression (DSC can go further).
public func largestModeFitting(lanes: Int, gbpsPerLane: Double) -> String? {
    let capacity = usableGbps(lanes: lanes, gbpsPerLane: gbpsPerLane)
    return commonModes.last { requiredGbps(width: $0.width, height: $0.height, hz: $0.hz) <= capacity }?.name
}
