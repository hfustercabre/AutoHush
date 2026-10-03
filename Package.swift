// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AutoHush",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "AutoHush", targets: ["AutoHush"])
    ],
    targets: [
        // App sources are grouped by feature: App, MenuBar, Settings, Audio,
        // Playback and MusicPlayers (one subfolder per supported app). Bundle
        // metadata lives in Resources/ and is assembled into AutoHush.app by
        // Scripts/build-app.sh.
        .executableTarget(name: "AutoHush"),
        .testTarget(
            name: "AutoHushTests",
            dependencies: ["AutoHush"]
        )
    ],
    swiftLanguageModes: [.v6]
)
