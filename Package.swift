// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BetterFan",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BetterFan", targets: ["BetterFan"]),
        .executable(name: "BetterFanHelper", targets: ["BetterFanHelper"]),
        .executable(name: "BetterFanProbe", targets: ["BetterFanProbe"]),
    ],
    targets: [
        .target(
            name: "FanControlCore",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("Security")]),
        .executableTarget(
            name: "BetterFan", dependencies: ["FanControlCore"],
            linkerSettings: [
                .linkedFramework("AppKit"), .linkedFramework("WebKit"),
                .linkedFramework("ServiceManagement"),
            ]),
        .executableTarget(name: "BetterFanHelper", dependencies: ["FanControlCore"]),
        .executableTarget(name: "BetterFanProbe", dependencies: ["FanControlCore"]),
        .testTarget(name: "FanControlCoreTests", dependencies: ["FanControlCore"]),
    ]
)
