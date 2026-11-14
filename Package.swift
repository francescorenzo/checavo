// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "CheCavo",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CableCore"),
        .target(name: "PortReader", dependencies: ["CableCore"], linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "usbc-dump", dependencies: ["CableCore", "PortReader"]),
        .executableTarget(name: "CheCavo", dependencies: ["CableCore", "PortReader"]),
        .testTarget(name: "CableCoreTests", dependencies: ["CableCore"]),
        .testTarget(name: "PortReaderTests", dependencies: ["PortReader", "CableCore"]),
    ]
)
