// swift-tools-version: 6.0
import PackageDescription

// AutoHush is split into modules, so the compiler keeps the layers apart:
//
//   AutoHush (executable, entry point only)
//     └─ AutoHushApp       menu bar, Settings, updates… and the app's wiring
//          ├─ AutoHushPlayers   the supported music players
//          │    └─ SpotifySupport   (one <App>Support target per player)
//          └─ AutoHushKit       the engine: audio detection, playback decisions,
//                               fades, the MusicPlayer interface, permissions,
//                               private APIs, configuration and storage
//
//   measure-volume-curve (executable) → AutoHushPlayers, AutoHushKit
//
// Code inside a module is grouped by domain. Types shared between modules use
// `package` access: visible inside this package, not to anyone else. Bundle
// metadata lives in Resources/ and is assembled into AutoHush.app by
// Scripts/build-app.sh.
let package = Package(
    name: "AutoHush",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "AutoHush", targets: ["AutoHush"]),
        .executable(name: "measure-volume-curve", targets: ["MeasureVolumeCurve"]),
    ],
    targets: [
        .executableTarget(name: "AutoHush", dependencies: ["AutoHushApp"]),
        .target(name: "AutoHushApp", dependencies: ["AutoHushKit", "AutoHushPlayers"]),
        .target(name: "AutoHushPlayers", dependencies: ["AutoHushKit", "SpotifySupport"]),
        .target(name: "SpotifySupport", dependencies: ["AutoHushKit"]),
        .target(name: "AutoHushKit"),

        // Measures a player's volume curve with the engine's own meter.
        .executableTarget(name: "MeasureVolumeCurve", dependencies: ["AutoHushKit", "AutoHushPlayers"]),

        // Fakes shared by the test targets.
        .target(name: "AutoHushTestSupport", dependencies: ["AutoHushKit"], path: "Tests/AutoHushTestSupport"),
        .testTarget(name: "AutoHushKitTests", dependencies: ["AutoHushKit", "AutoHushTestSupport"]),
        .testTarget(name: "SpotifySupportTests", dependencies: ["SpotifySupport", "AutoHushKit", "AutoHushTestSupport"]),
        .testTarget(
            name: "AutoHushAppTests",
            dependencies: ["AutoHushApp", "AutoHushPlayers", "SpotifySupport", "AutoHushKit", "AutoHushTestSupport"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
