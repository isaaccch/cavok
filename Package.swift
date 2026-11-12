// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Cavok",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "CavokKit"),
        .executableTarget(
            name: "Cavok",
            dependencies: ["CavokKit"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "CavokKitTests", dependencies: ["CavokKit"]),
    ]
)
