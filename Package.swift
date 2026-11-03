// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Temperatura",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ThermalCore"),
        .executableTarget(name: "Temperatura", dependencies: ["ThermalCore"]),
        .testTarget(name: "ThermalCoreTests", dependencies: ["ThermalCore"]),
    ]
)
