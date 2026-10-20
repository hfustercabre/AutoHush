// swift-tools-version: 6.0
import PackageDescription

// AutoHush is split into modules, so the compiler keeps the layers apart:
// the app, the engine (AutoHushKit), one module per media player and the
// ones they share, the check (playercheck and PlayerCheckKit) and its panel
// (CheckPanel), and the tools in Tools/. DEVELOPMENT.md's Architecture draws
// them and what each depends on; this file only declares them.
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
        .executable(name: "PlayerCheckApp", targets: ["PlayerCheckApp"]),
    ],
    targets: [
        .executableTarget(name: "AutoHush", dependencies: ["AutoHushApp"]),
        // CheckedPlayers for Add an App…: what a check found, and keeping it;
        // PlayerCheckKit and CheckPanel to run the check and show its panel.
        .target(name: "AutoHushApp", dependencies: ["AutoHushKit", "AutoHushPlayers", "CheckedPlayers", "PlayerCheckKit", "CheckPanel"]),
        .target(
            name: "AutoHushPlayers",
            dependencies: [
                "AutoHushKit", "ScriptablePlayers", "MenuPlayers", "WebAppPlayers", "CheckedPlayers",
                "SpotifySupport", "AppleMusicSupport", "TidalSupport", "PodcastsSupport", "VLCSupport", "QuickTimeSupport",
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
        .target(
            name: "QuickTimeSupport",
            dependencies: ["AutoHushKit", "ScriptablePlayers"],
            path: "Sources/PlayersSupport/QuickTimeSupport"
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

        // Player Check: playercheck in a window, for any app, with the check's
        // panel as Add an App… shows it. A public tool, built into an app by
        // its build.sh: never part of AutoHush.app.
        .executableTarget(
            name: "PlayerCheckApp",
            dependencies: ["PlayerCheckKit", "CheckedPlayers", "CheckPanel", "AutoHushKit"],
            path: "Tools/PlayerCheckApp",
            exclude: ["README.md", "Info.plist", "build.sh"]
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
        // The check's parts that need no app to check: its command line, exit
        // statuses and answers (what AutoHush and the Player Check app run it
        // with), reading an app's binaries, what its log leaves out and how
        // it's named, what it keeps, judging a press, handling a stop, and
        // what it found as its result.
        .target(
            name: "PlayerCheckKit",
            dependencies: ["AutoHushKit", "WebAppPlayers", "CheckedPlayers", "ScriptablePlayers"],
            path: "Sources/PlayerCheck/Kit"
        ),
        // The check's panel and its shade, shown by whoever runs a check
        // (AutoHush's Add an App…, the Player Check app).
        .target(name: "CheckPanel", dependencies: ["PlayerCheckKit"]),

        // Fakes shared by the test targets: the engine's, and the players'
        // (their stores, Now Playing's setting, a scripted app's events).
        .target(name: "AutoHushTestSupport", dependencies: ["AutoHushKit"], path: "Tests/AutoHushTestSupport"),
        .target(
            name: "PlayersTestSupport",
            dependencies: ["AutoHushTestSupport", "AutoHushKit", "ScriptablePlayers", "WebAppPlayers", "CheckedPlayers"],
            path: "Tests/PlayersTestSupport"
        ),
        .testTarget(name: "AutoHushKitTests", dependencies: ["AutoHushKit", "AutoHushTestSupport"]),
        .testTarget(
            name: "ScriptablePlayersTests",
            dependencies: ["ScriptablePlayers", "AutoHushKit", "AutoHushTestSupport", "PlayersTestSupport"],
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
            dependencies: ["WebAppPlayers", "AutoHushKit", "AutoHushTestSupport", "PlayersTestSupport"],
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
            dependencies: ["CheckedPlayers", "ScriptablePlayers", "WebAppPlayers", "AutoHushKit", "AutoHushTestSupport", "PlayersTestSupport"],
            path: "Tests/PlayersSupport/CheckedPlayersTests"
        ),
        .testTarget(
            name: "VLCSupportTests",
            dependencies: ["VLCSupport", "ScriptablePlayers", "AutoHushKit", "PlayersTestSupport"],
            path: "Tests/PlayersSupport/VLCSupportTests"
        ),
        .testTarget(
            name: "QuickTimeSupportTests",
            dependencies: ["QuickTimeSupport", "ScriptablePlayers", "AutoHushKit"],
            path: "Tests/PlayersSupport/QuickTimeSupportTests"
        ),
        // The helper itself, run as a read-only check of an app on the Mac.
        .testTarget(
            name: "PlayerCheckTests",
            dependencies: ["PlayerCheck", "PlayerCheckKit", "CheckedPlayers", "ScriptablePlayers", "WebAppPlayers", "AutoHushKit", "AutoHushTestSupport"],
            path: "Tests/PlayerCheckTests"
        ),
        // AutoHushPlayers only for the supported players' names, which no
        // file of Sources/PlayerCheck may hold.
        .testTarget(
            name: "PlayerCheckKitTests",
            dependencies: [
                "PlayerCheckKit", "CheckedPlayers", "ScriptablePlayers", "WebAppPlayers", "AutoHushKit", "AutoHushTestSupport",
            ],
            path: "Tests/PlayerCheckKitTests"
        ),
        .testTarget(name: "CheckPanelTests", dependencies: ["CheckPanel", "PlayerCheckKit"]),
        .testTarget(
            name: "AutoHushAppTests",
            dependencies: [
                "AutoHushApp", "AutoHushKit", "CheckedPlayers", "WebAppPlayers", "PlayerCheckKit", "CheckPanel",
                "AutoHushTestSupport", "PlayersTestSupport",
            ]
        ),
        // CheckedPlayers to keep an added app, as Add an App does.
        .testTarget(
            name: "AutoHushPlayersTests",
            dependencies: [
                "AutoHushPlayers", "ScriptablePlayers", "MenuPlayers", "WebAppPlayers", "CheckedPlayers",
                "SpotifySupport", "AppleMusicSupport", "TidalSupport", "PodcastsSupport", "VLCSupport", "QuickTimeSupport",
                "AutoHushKit",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
