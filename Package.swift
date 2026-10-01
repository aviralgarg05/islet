// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Islet",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Islet", targets: ["Islet"]),
        .executable(name: "isletctl", targets: ["isletctl"]),
        .library(name: "IsletCore", targets: ["IsletCore"]),
    ],
    targets: [
        // Pure, platform-light logic: models, arbitration, parsing, geometry.
        // Everything here is unit-tested and must not touch AppKit or private APIs.
        .target(
            name: "IsletCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Adapters to macOS services (CoreAudio, IOKit, EventKit, media players, local API server).
        .target(
            name: "IsletSystem",
            dependencies: ["IsletCore"],
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
            name: "Islet",
            dependencies: ["IsletCore", "IsletSystem"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Command-line client for the local API (scripts, hooks, CI, Raycast, etc.).
        .executableTarget(
            name: "isletctl",
            dependencies: ["IsletCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "IsletCoreTests",
            dependencies: ["IsletCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "IsletSystemTests",
            dependencies: ["IsletCore", "IsletSystem"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
