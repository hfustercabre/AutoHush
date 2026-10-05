// swift-tools-version: 6.0
import PackageDescription

// AutoHush is split into modules, so the compiler keeps the layers apart:
//
//   AutoHush (executable, entry point only)
//     └─ AutoHushApp       menu bar, Settings, updates… and the app's wiring
//          ├─ AutoHushPlayers   the supported music players
//          │    ├─ SpotifySupport, AppleMusicSupport, TidalSupport
//          │    │                   one <App>Support target per player, all in
//          │    │                   Sources/PlayersSupport/: what's special about it
//          │    └─ ScriptablePlayers  controls any app scripted with Apple events
//          │                        (state, pause, play, volume, its notification)
//          └─ AutoHushKit       the engine: audio detection, playback decisions,
//                               fades, the MusicPlayer interface, permissions,
//                               private APIs, configuration and storage
//
//   measure-volume-curve (developer tool, in Tools/) → AutoHushPlayers, AutoHushKit
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
        .target(
            name: "AutoHushPlayers",
            dependencies: ["AutoHushKit", "ScriptablePlayers", "SpotifySupport", "AppleMusicSupport", "TidalSupport"]
        ),
        .target(name: "ScriptablePlayers", dependencies: ["AutoHushKit"], path: "Sources/PlayersSupport/ScriptablePlayers"),
        .target(
            name: "SpotifySupport",
            dependencies: ["AutoHushKit", "ScriptablePlayers"],
            path: "Sources/PlayersSupport/SpotifySupport"
        ),
        .target(
            name: "AppleMusicSupport",
            dependencies: ["AutoHushKit", "ScriptablePlayers"],
            path: "Sources/PlayersSupport/AppleMusicSupport"
        ),
        .target(name: "TidalSupport", dependencies: ["AutoHushKit"], path: "Sources/PlayersSupport/TidalSupport"),
        .target(name: "AutoHushKit"),

        // Measures a player's volume curve with the engine's own meter. A
        // developer tool: never part of AutoHush.app.
        .executableTarget(
            name: "MeasureVolumeCurve",
            dependencies: ["AutoHushKit", "AutoHushPlayers"],
            path: "Tools/MeasureVolumeCurve"
        ),

        // Fakes shared by the test targets.
        .target(name: "AutoHushTestSupport", dependencies: ["AutoHushKit"], path: "Tests/AutoHushTestSupport"),
        .testTarget(name: "AutoHushKitTests", dependencies: ["AutoHushKit", "AutoHushTestSupport"]),
        .testTarget(
            name: "ScriptablePlayersTests",
            dependencies: ["ScriptablePlayers", "AutoHushKit"],
            path: "Tests/PlayersSupport/ScriptablePlayersTests"
        ),
        .testTarget(
            name: "SpotifySupportTests",
            dependencies: ["SpotifySupport", "ScriptablePlayers", "AutoHushKit"],
            path: "Tests/PlayersSupport/SpotifySupportTests"
        ),
        .testTarget(
            name: "AppleMusicSupportTests",
            dependencies: ["AppleMusicSupport", "ScriptablePlayers", "AutoHushKit"],
            path: "Tests/PlayersSupport/AppleMusicSupportTests"
        ),
        .testTarget(
            name: "TidalSupportTests",
            dependencies: ["TidalSupport", "AutoHushKit"],
            path: "Tests/PlayersSupport/TidalSupportTests"
        ),
        .testTarget(
            name: "AutoHushAppTests",
            dependencies: ["AutoHushApp", "AutoHushKit", "AutoHushTestSupport"]
        ),
        .testTarget(
            name: "AutoHushPlayersTests",
            dependencies: ["AutoHushPlayers", "ScriptablePlayers", "SpotifySupport", "AppleMusicSupport", "TidalSupport", "AutoHushKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
