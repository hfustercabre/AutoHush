// swift-tools-version: 6.0
import PackageDescription

// AutoHush is split into modules, so the compiler keeps the layers apart:
//
//   AutoHush (executable, entry point only)
//     └─ AutoHushApp       menu bar, Settings, updates… and the app's wiring
//          ├─ AutoHushPlayers   the supported media players
//          │    ├─ SpotifySupport, AppleMusicSupport, TidalSupport…
//          │    │                   one <App>Support target per player, all in
//          │    │                   Sources/PlayersSupport/: what's special about it
//          │    ├─ ScriptablePlayers  controls any app scripted with Apple events
//          │    │                   (state, pause, play, volume, its notification)
//          │    ├─ MenuPlayers      controls an app through its playback menu
//          │    ├─ WebAppPlayers    controls Safari web apps through the site's
//          │    │                   own Play/Pause button, learned once
//          │    └─ CheckedPlayers   controls an app added with Add an App…, the
//          │                        way the user chose (on the three above)
//          ├─ CheckedPlayers    Add an App…'s check results and its report's lines
//          └─ AutoHushKit       the engine: audio detection, playback decisions,
//                               fades, the MusicPlayer interface, permissions,
//                               private APIs, configuration and storage
//
//   measure-volume-curve (developer tool, in Tools/) → AutoHushPlayers, AutoHushKit
//   listen-to-fades (developer tool, in Tools/): records a loopback device
//                               and measures AutoHush's fades in it
//   playercheck (AutoHush.app's helper, in Sources/PlayerCheck) → PlayerCheckKit,
//                               ScriptablePlayers, MenuPlayers, WebAppPlayers,
//                               CheckedPlayers, AutoHushKit: whether and how
//                               AutoHush could control an app, checked with
//                               AutoHush's own code (Add an App… runs it); it
//                               names no player
//     └─ PlayerCheckKit    its parts that need no app to check (in its Kit/
//                          folder), so tests can reach them
//
// Code inside a module is sorted by kind of code first (Models, Services,
// Views…), then by area. Types shared between modules use `package` access:
// visible inside this package, not to anyone else. Bundle metadata lives in
// Resources/ and is assembled into AutoHush.app by Scripts/build-app.sh.
let package = Package(
    name: "AutoHush",
    platforms: [
        .macOS("14.4")
    ],
    products: [
        .executable(name: "AutoHush", targets: ["AutoHush"]),
        .executable(name: "measure-volume-curve", targets: ["MeasureVolumeCurve"]),
        .executable(name: "listen-to-fades", targets: ["ListenToFades"]),
        .executable(name: "playercheck", targets: ["PlayerCheck"]),
    ],
    targets: [
        .executableTarget(name: "AutoHush", dependencies: ["AutoHushApp"]),
        // CheckedPlayers for Add an App…: what a check found, and keeping it.
        .target(name: "AutoHushApp", dependencies: ["AutoHushKit", "AutoHushPlayers", "CheckedPlayers"]),
        .target(
            name: "AutoHushPlayers",
            dependencies: [
                "AutoHushKit", "ScriptablePlayers", "MenuPlayers", "WebAppPlayers", "CheckedPlayers",
                "SpotifySupport", "AppleMusicSupport", "TidalSupport", "PodcastsSupport", "VLCSupport",
            ]
        ),
        .target(name: "ScriptablePlayers", dependencies: ["AutoHushKit"], path: "Sources/PlayersSupport/ScriptablePlayers"),
        .target(name: "MenuPlayers", dependencies: ["AutoHushKit"], path: "Sources/PlayersSupport/MenuPlayers"),
        .target(name: "WebAppPlayers", dependencies: ["AutoHushKit"], path: "Sources/PlayersSupport/WebAppPlayers"),
        // Apps added with Add an App…: controlled the way the user chose.
        .target(
            name: "CheckedPlayers",
            dependencies: ["AutoHushKit", "ScriptablePlayers", "MenuPlayers", "WebAppPlayers"],
            path: "Sources/PlayersSupport/CheckedPlayers"
        ),
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
            path: "Tools/MeasureVolumeCurve",
            exclude: ["README.md"]
        ),

        // Records a loopback audio device and measures AutoHush's fades in it,
        // as you hear them. A developer tool: never part of AutoHush.app.
        .executableTarget(
            name: "ListenToFades",
            path: "Tools/ListenToFades",
            exclude: ["README.md"]
        ),

        // Checks whether and how AutoHush could control an app, with AutoHush's
        // own code for what they share (Apple events, menus, learned page
        // buttons, sound). AutoHush.app carries it as a helper, which Add an
        // App… runs (its own process: a check that ends, or stops, takes its
        // block on the mouse and keyboard with it). Its files are split by
        // subject, with main.swift's top-level code running the steps.
        .executableTarget(
            name: "PlayerCheck",
            dependencies: ["PlayerCheckKit", "AutoHushKit", "ScriptablePlayers", "MenuPlayers", "WebAppPlayers", "CheckedPlayers"],
            path: "Sources/PlayerCheck",
            exclude: ["README.md", "Kit"]
        ),
        // The check's parts that need no app to check: reading its command
        // line and an app's binaries, what its log leaves out, what it keeps.
        .target(
            name: "PlayerCheckKit",
            dependencies: ["AutoHushKit", "WebAppPlayers", "CheckedPlayers", "ScriptablePlayers"],
            path: "Sources/PlayerCheck/Kit"
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
            name: "CheckedPlayersTests",
            dependencies: ["CheckedPlayers", "ScriptablePlayers", "WebAppPlayers", "AutoHushKit", "AutoHushTestSupport"],
            path: "Tests/PlayersSupport/CheckedPlayersTests"
        ),
        .testTarget(
            name: "VLCSupportTests",
            dependencies: ["VLCSupport", "ScriptablePlayers", "AutoHushKit"],
            path: "Tests/PlayersSupport/VLCSupportTests"
        ),
        // AutoHushPlayers only for the supported players' names, which no
        // file of Sources/PlayerCheck may hold.
        .testTarget(
            name: "PlayerCheckKitTests",
            dependencies: ["PlayerCheckKit", "CheckedPlayers", "ScriptablePlayers", "WebAppPlayers", "AutoHushKit", "AutoHushPlayers"],
            path: "Tests/PlayerCheckKitTests"
        ),
        .testTarget(
            name: "AutoHushAppTests",
            dependencies: ["AutoHushApp", "AutoHushKit", "CheckedPlayers", "AutoHushTestSupport"]
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
