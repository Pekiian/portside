// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Portside",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Portside",
            dependencies: ["PortsideCore"]
        ),
        .target(name: "PortsideCore"),
        .testTarget(
            name: "PortsideCoreTests",
            dependencies: ["PortsideCore"]
        ),
    ]
)
