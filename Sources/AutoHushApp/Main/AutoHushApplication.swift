import AppKit
import AutoHushKit

/// Starts AutoHush: a menu bar accessory app driven by `AppDelegate`.
public enum AutoHushApplication {
    @MainActor
    public static func run() {
        // Started by itself only to say which app is Now Playing (a fresh
        // process gets a fresh answer: see `NowPlayingApp`): it answers and
        // quits before anything of the app starts.
        if CommandLine.arguments.dropFirst().first == NowPlayingApp.argument {
            NowPlayingApp.printAnswer()
            exit(0)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run() // never returns; `delegate` stays alive for the app's lifetime
    }
}
