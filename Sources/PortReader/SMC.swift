import CableCore
import IOKit

/// The Mac's DC-in sensors (watts, volts, amps) from the SMC: refreshed every second and readable without admin
/// rights, unlike the battery telemetry, which updates once a minute and keeps the previous cable's values.
// shortcut: keys PDTR/VD0R/ID0R seen on the MacBook Pro M3 (macOS 27.0.1); a Mac without them shows no measured
// power, only what the charger offers. Check new Mac models with "Copia dati grezzi".
final class SMC {
    private var connection: io_connect_t = 0

    init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        if IOServiceOpen(service, mach_task_self_, 0, &connection) != KERN_SUCCESS { connection = 0 }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    func powerIn() -> PowerIn? {
        smcPowerIn(watts: float("PDTR"), volts: float("VD0R"), amps: float("ID0R"))
    }

    /// nil when the key is missing or is not a 4-byte float.
    private func float(_ key: String) -> Double? {
        guard connection != 0 else { return nil }
        var info = SMCKeyData(key: key, command: SMCKeyData.readKeyInfo)
        guard call(&info), info.dataSize == 4, info.dataType == fourCC("flt ") else { return nil }
        var value = SMCKeyData(key: key, command: SMCKeyData.readBytes)
        value.dataSize = 4
        guard call(&value) else { return nil }
        let raw = UInt32(value.bytes.0) | UInt32(value.bytes.1) << 8 | UInt32(value.bytes.2) << 16 | UInt32(value.bytes.3) << 24
        return Double(Float(bitPattern: raw))
    }

    private func call(_ data: inout SMCKeyData) -> Bool {
        var output = SMCKeyData()
        var size = MemoryLayout<SMCKeyData>.stride
        let status = IOConnectCallStructMethod(connection, SMCKeyData.handleEvent, &data, MemoryLayout<SMCKeyData>.stride,
                                               &output, &size)
        data = output
        return status == KERN_SUCCESS && output.result == 0
    }
}

/// Below half a watt the Mac is on battery.
func smcPowerIn(watts: Double?, volts: Double?, amps: Double?) -> PowerIn? {
    guard let watts, let volts, let amps, watts >= 0.5 else { return nil }
    return PowerIn(milliwatts: Int((watts * 1000).rounded()), millivolts: Int((volts * 1000).rounded()),
                   milliamps: Int((amps * 1000).rounded()))
}

func fourCC(_ text: String) -> UInt32 { text.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

/// The kernel's SMCKeyData_t, 80 bytes; Swift does not pad nested structs like C, so the padding is spelled out.
struct SMCKeyData {
    static let handleEvent: UInt32 = 2
    static let readBytes: UInt8 = 5
    static let readKeyInfo: UInt8 = 9

    var key: UInt32 = 0
    var version: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0, 0, 0, 0, 0)
    var powerLimit: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    var padding: (UInt8, UInt8, UInt8) = (0, 0, 0)
    var result: UInt8 = 0
    var status: UInt8 = 0
    var command: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
        = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

    init() {}

    init(key: String, command: UInt8) {
        self.key = fourCC(key)
        self.command = command
    }
}
