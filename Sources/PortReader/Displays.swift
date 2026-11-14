import CableCore
import CoreAudio
import CoreGraphics

/// Every monitor macOS drives now, with its EDID identity and current mode.
public func onlineDisplays() -> [(DisplayID, DisplayMode?)] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 32)
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
    return ids.prefix(Int(count)).compactMap { id in
        guard let mode = CGDisplayCopyDisplayMode(id) else { return nil }
        // kept even without a mode, so an identical monitor is not matched to this one's port
        return (DisplayID(vendor: UInt16(truncatingIfNeeded: CGDisplayVendorNumber(id)),
                          product: UInt16(truncatingIfNeeded: CGDisplayModelNumber(id)),
                          serial: CGDisplaySerialNumber(id)),
                signalMode(DisplayMode(width: mode.pixelWidth, height: mode.pixelHeight, hz: mode.refreshRate),
                           native: nativeSize(id)))
    }
}

/// The mode in the cable. A scaled HiDPI mode renders more pixels than the panel has and sends the native size;
/// a mode smaller than the panel may be scaled up before sending, so its size in the cable is unknown.
// shortcut: assumes Apple Silicon sends the native size for scaled modes; seen on the built-in panel only,
// check with a 4K monitor on "More space" in "Copia dati grezzi".
func signalMode(_ current: DisplayMode, native: (width: Int, height: Int)?) -> DisplayMode? {
    guard let native, (current.width, current.height) != native else { return current }
    return current.width > native.width ? DisplayMode(width: native.width, height: native.height, hz: current.hz) : nil
}

/// The panel's own size, from the mode macOS flags as native (the largest 1x mode is not it on the built-in panel).
private func nativeSize(_ id: CGDirectDisplayID) -> (width: Int, height: Int)? {
    let kDisplayModeNativeFlag: UInt32 = 0x0200_0000
    let modes = CGDisplayCopyAllDisplayModes(id, nil) as? [CGDisplayMode] ?? []
    return modes.first { $0.ioFlags & kDisplayModeNativeFlag != 0 }.map { ($0.pixelWidth, $0.pixelHeight) }
}

/// macOS audio outputs that go to a monitor (DisplayPort or HDMI), with their UID and output channels.
public func displayAudioOutputs() -> [(uid: String, channels: Int)] {
    let system = AudioObjectID(kAudioObjectSystemObject)
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                             mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
    return ids.compactMap { id in
        guard let transport = transportType(id),
              transport == kAudioDeviceTransportTypeDisplayPort || transport == kAudioDeviceTransportTypeHDMI,
              let uid = deviceUID(id) else { return nil }
        let channels = outputChannels(id)
        return channels > 0 ? (uid, channels) : nil
    }
}

private func transportType(_ id: AudioObjectID) -> UInt32? {
    var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                             mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? value : nil
}

private func deviceUID(_ id: AudioObjectID) -> String? {
    var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
                                             mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
    var uid: CFString?
    var size = UInt32(MemoryLayout<CFString?>.size)
    let status = withUnsafeMutablePointer(to: &uid) { AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0) }
    return status == noErr ? uid as String? : nil
}

private func outputChannels(_ id: AudioObjectID) -> Int {
    var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                             mScope: kAudioObjectPropertyScopeOutput,
                                             mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { buffer.deallocate() }
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr else { return 0 }
    let list = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
    return list.reduce(0) { $0 + Int($1.mNumberChannels) }
}
