import CableCore
import Foundation
import IOKit

/// Every IORegistry entry that declares itself a USB-C port, with its whole subtree.
public func readRegistryPorts() -> [RegistryNode] {
    let matching = IOServiceMatching("IOService") as NSMutableDictionary
    matching["IOPropertyMatch"] = ["PortTypeDescription": "USB-C"]
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
    defer { IOObjectRelease(iterator) }
    var nodes: [RegistryNode] = []
    while case let entry = IOIteratorNext(iterator), entry != 0 {
        nodes.append(registryNode(entry))
        IOObjectRelease(entry)
    }
    return sortedPorts(nodes)
}

private func registryNode(_ entry: io_registry_entry_t) -> RegistryNode {
    let className = IOObjectCopyClass(entry)?.takeRetainedValue() as String? ?? ""
    let nameBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: 128)  // io_name_t
    defer { nameBuffer.deallocate() }
    let name = IORegistryEntryGetName(entry, nameBuffer) == KERN_SUCCESS ? String(cString: nameBuffer) : ""

    var cfProperties: Unmanaged<CFMutableDictionary>?
    IORegistryEntryCreateCFProperties(entry, &cfProperties, kCFAllocatorDefault, 0)
    let properties = cfProperties?.takeRetainedValue() as? [String: Any] ?? [:]

    var children: [RegistryNode] = []
    var iterator: io_iterator_t = 0
    if IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iterator) == KERN_SUCCESS {
        while case let child = IOIteratorNext(iterator), child != 0 {
            children.append(registryNode(child))
            IOObjectRelease(child)
        }
        IOObjectRelease(iterator)
    }
    return RegistryNode(className: className, name: name, properties: properties, children: children)
}

/// Ports the Mac draws power from now, MagSafe included ("Port-MagSafe 3@1", "Port-USB-C@1").
public func powerInputs() -> Set<String> {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(powerSourceClass), &iterator) == KERN_SUCCESS
    else { return [] }
    defer { IOObjectRelease(iterator) }
    var names: Set<String> = []
    while case let entry = IOIteratorNext(iterator), entry != 0 {
        var cfProperties: Unmanaged<CFMutableDictionary>?
        if IORegistryEntryCreateCFProperties(entry, &cfProperties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
           let properties = cfProperties?.takeRetainedValue() as? [String: Any],
           let name = powerInputName(properties) {
            names.insert(name)
        }
        IOObjectRelease(entry)
    }
    return names
}
