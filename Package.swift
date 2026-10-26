// swift-tools-version: 6.4
import PackageDescription

// Design section 9. DollyCore is pure (no AppKit, no ScreenCaptureKit), DollySystem is the only
// target that touches ScreenCaptureKit, Carbon and input polling, and dollyctl never links either.
let mainActorByDefault: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "Dolly",
    platforms: [.macOS(.v27)],
    products: [
        .executable(name: "Dolly", targets: ["Dolly"]),
        .executable(name: "dollyctl", targets: ["dollyctl"]),
    ],
    dependencies: [
        // Auto-update (app-updates CONTRACT.md). Only the Dolly app target links it.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(name: "DollyCore"),
        .target(name: "DollyRender", dependencies: ["DollyCore"]),
        .target(
            name: "DollySystem",
            dependencies: ["DollyCore"],
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Carbon"),
            ]
        ),
        .target(name: "DollyUI", dependencies: ["DollyCore", "DollyRender"], swiftSettings: mainActorByDefault),
        .executableTarget(
            name: "Dolly",
            dependencies: ["DollyUI", "DollyRender", "DollySystem", "DollyCore", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: mainActorByDefault
        ),
        .executableTarget(name: "dollyctl", dependencies: ["DollyCore", "DollyRender"]),
        .testTarget(name: "DollyCoreTests", dependencies: ["DollyCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "DollyRenderTests", dependencies: ["DollyRender", "DollyCore"]),
        .testTarget(name: "DollySystemTests", dependencies: ["DollySystem", "DollyCore"]),
        .testTarget(name: "DollyUITests", dependencies: ["DollyUI", "DollyCore"]),
    ],
    swiftLanguageModes: [.v6]
)
