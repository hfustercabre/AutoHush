import AppKit
import AutoHushKit

/// Starts AutoHush: a menu bar accessory app driven by `AppDelegate`.
package enum AutoHushApplication {
    @MainActor
    package static func run() {
        // Started by itself only to say which app is Now Playing (a fresh
        // process gets a fresh answer: see `NowPlayingApp`): it answers and
        // quits before anything of the app starts.
        if CommandLine.arguments.dropFirst().first == NowPlayingApp.argument {
            NowPlayingApp.printAnswer()
            exit(0)
        }
        // AutoHush's own log of the last 24 hours: ~/Library/Logs/AutoHush.
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        LogFile.start(at: logs.appending(path: "Logs/AutoHush/AutoHush.log"))
        // No tabs and no Enter Full Screen: AppKit adds them to the View and
        // Window menus by itself, and AutoHush's windows use neither (the
        // user, 2026-10-25). Before the app starts, when AppKit reads them.
        NSWindow.allowsAutomaticWindowTabbing = false
        UserDefaults.standard.register(defaults: ["NSFullScreenMenuItemEverywhere": false])
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run() // never returns; `delegate` stays alive for the app's lifetime
    }
}
