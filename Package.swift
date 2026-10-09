// swift-tools-version: 6.0
import PackageDescription

// AutoHush is split into modules, so the compiler keeps the layers apart:
//
//   AutoHush (executable, entry point only)
//     └─ AutoHushApp       menu bar, Settings, updates… and the app's wiring
//          ├─ AutoHushPlayers   the supported music players
//          │    ├─ SpotifySupport, AppleMusicSupport, TidalSupport…
//          │    │                   one <App>Support target per player, all in
//          │    │                   Sources/PlayersSupport/: what's special about it
//          │    ├─ ScriptablePlayers  controls any app scripted with Apple events
//          │    │                   (state, pause, play, volume, its notification)
//          │    ├─ MenuPlayers      controls an app through its playback menu
//          │    └─ WebAppPlayers    controls Safari web apps through the site's
//          │                        own Play/Pause button, learned once
//          └─ AutoHushKit       the engine: audio detection, playback decisions,
//                               fades, the MusicPlayer interface, permissions,
//                               private APIs, configuration and storage
//
//   measure-volume-curve (developer tool, in DevTools/) → AutoHushPlayers, AutoHushKit
//   listen-to-fades (developer tool, in DevTools/): records a loopback device
//                               and measures AutoHush's fades in it
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
        .executable(name: "listen-to-fades", targets: ["ListenToFades"]),
    ],
    targets: [
        .executableTarget(name: "AutoHush", dependencies: ["AutoHushApp"]),
        .target(name: "AutoHushApp", dependencies: ["AutoHushKit", "AutoHushPlayers"]),
        .target(
            name: "AutoHushPlayers",
            dependencies: [
                "AutoHushKit", "ScriptablePlayers", "MenuPlayers", "WebAppPlayers",
                "SpotifySupport", "AppleMusicSupport", "TidalSupport", "PodcastsSupport", "VLCSupport",
            ]
        ),
        .target(name: "ScriptablePlayers", dependencies: ["AutoHushKit"], path: "Sources/PlayersSupport/ScriptablePlayers"),
        .target(name: "MenuPlayers", dependencies: ["AutoHushKit"], path: "Sources/PlayersSupport/MenuPlayers"),
        .target(name: "WebAppPlayers", dependencies: ["AutoHushKit"], path: "Sources/PlayersSupport/WebAppPlayers"),
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
        .target(name: "TidalSupport", dependencies: ["AutoHushKit", "MenuPlayers"], path: "Sources/PlayersSupport/TidalSupport"),
        .target(
            name: "PodcastsSupport",
            dependencies: ["AutoHushKit", "MenuPlayers"],
            path: "Sources/PlayersSupport/PodcastsSupport"
        ),
        .target(
            name: "VLCSupport",
            dependencies: ["AutoHushKit", "ScriptablePlayers"],
            path: "Sources/PlayersSupport/VLCSupport"
        ),
        .target(name: "AutoHushKit"),

        // Measures a player's volume curve with the engine's own meter. A
        // developer tool: never part of AutoHush.app.
        .executableTarget(
            name: "MeasureVolumeCurve",
            dependencies: ["AutoHushKit", "AutoHushPlayers"],
            path: "DevTools/MeasureVolumeCurve",
            exclude: ["README.md"]
        ),

        // Records a loopback audio device and measures AutoHush's fades in it,
        // as you hear them. A developer tool: never part of AutoHush.app.
        .executableTarget(
            name: "ListenToFades",
            path: "DevTools/ListenToFades",
            exclude: ["README.md"]
        ),

        // Fakes shared by the test targets.
        .target(name: "AutoHushTestSupport", dependencies: ["AutoHushKit"], path: "Tests/AutoHushTestSupport"),
        .testTarget(name: "AutoHushKitTests", dependencies: ["AutoHushKit", "AutoHushTestSupport"]),
        .testTarget(
            name: "ScriptablePlayersTests",
            dependencies: ["ScriptablePlayers", "AutoHushKit", "AutoHushTestSupport"],
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
            name: "MenuPlayersTests",
            dependencies: ["MenuPlayers", "AutoHushKit", "AutoHushTestSupport"],
            path: "Tests/PlayersSupport/MenuPlayersTests"
        ),
        .testTarget(
            name: "WebAppPlayersTests",
            dependencies: ["WebAppPlayers", "AutoHushKit", "AutoHushTestSupport"],
            path: "Tests/PlayersSupport/WebAppPlayersTests"
        ),
        .testTarget(
            name: "TidalSupportTests",
            dependencies: ["TidalSupport", "MenuPlayers", "AutoHushKit"],
            path: "Tests/PlayersSupport/TidalSupportTests"
        ),
        .testTarget(
            name: "PodcastsSupportTests",
            dependencies: ["PodcastsSupport", "MenuPlayers", "AutoHushKit"],
            path: "Tests/PlayersSupport/PodcastsSupportTests"
        ),
        .testTarget(
            name: "VLCSupportTests",
            dependencies: ["VLCSupport", "ScriptablePlayers", "AutoHushKit"],
            path: "Tests/PlayersSupport/VLCSupportTests"
        ),
        .testTarget(
            name: "AutoHushAppTests",
            dependencies: ["AutoHushApp", "AutoHushKit", "AutoHushTestSupport"]
        ),
        .testTarget(
            name: "AutoHushPlayersTests",
            dependencies: [
                "AutoHushPlayers", "ScriptablePlayers", "MenuPlayers", "WebAppPlayers",
                "SpotifySupport", "AppleMusicSupport", "TidalSupport", "PodcastsSupport", "VLCSupport", "AutoHushKit",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
