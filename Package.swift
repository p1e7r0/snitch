// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Snitch",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "SnitchCore"),
        .executableTarget(
            name: "Snitch",
            dependencies: ["SnitchCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "SnitchCoreTests", dependencies: ["SnitchCore"]),
    ]
)
