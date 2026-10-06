// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Casement",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Casement", targets: ["Casement"]),
        .executable(name: "casementctl", targets: ["casementctl"]),
        .library(name: "CasementCore", targets: ["CasementCore"]),
    ],
    targets: [
        // Pure, platform-light logic: models, arbitration, parsing, geometry.
        // Everything here is unit-tested and must not touch AppKit or private APIs.
        .target(
            name: "CasementCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Adapters to macOS services (CoreAudio, IOKit, EventKit, media players, local API server).
        .target(
            name: "CasementSystem",
            dependencies: ["CasementCore"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("EventKit"),
                .linkedFramework("Network"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreMediaIO"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("AVFoundation"),
            ]
        ),
        // The menu-bar agent app: notch panel, SwiftUI views, settings.
        .executableTarget(
            name: "Casement",
            dependencies: ["CasementCore", "CasementSystem"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Command-line client for the local API (scripts, hooks, CI, Raycast, etc.).
        .executableTarget(
            name: "casementctl",
            dependencies: ["CasementCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CasementCoreTests",
            dependencies: ["CasementCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CasementSystemTests",
            dependencies: ["CasementCore", "CasementSystem"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
