// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Cavok",
    platforms: [.macOS(.v26)],
    targets: [
        .target(
            name: "CavokSys",
            path: "Sources/CavokSys",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("proc"),
                .linkedLibrary("bsm"),
            ]
        ),
        .target(name: "CavokKit", dependencies: ["CavokSys"]),
        .executableTarget(
            name: "CavokGuardFilter",
            dependencies: ["CavokKit"],
            linkerSettings: [
                .linkedFramework("NetworkExtension"),
            ]
        ),
        .executableTarget(
            name: "Cavok",
            dependencies: ["CavokKit"],
            swiftSettings: [.defaultIsolation(MainActor.self)],
            linkerSettings: [
                .linkedFramework("NetworkExtension"),
                .linkedFramework("SystemExtensions"),
            ]
        ),
        .testTarget(name: "CavokKitTests", dependencies: ["CavokKit"]),
    ]
)
