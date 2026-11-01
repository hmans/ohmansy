// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ohmansy",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Ohmansy", targets: ["Ohmansy"])],
    targets: [
        .target(name: "VMStorage"),
        .target(name: "VMDisplay"),
        .executableTarget(name: "Ohmansy", dependencies: ["VMStorage", "VMDisplay"]),
        .executableTarget(name: "GraphicsProbe"),
        .testTarget(name: "VMStorageTests", dependencies: ["VMStorage"]),
        .testTarget(name: "VMDisplayTests", dependencies: ["VMDisplay"]),
    ]
)
