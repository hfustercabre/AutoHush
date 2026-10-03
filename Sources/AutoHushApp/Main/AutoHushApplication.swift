import AppKit

/// Starts AutoHush: a menu bar accessory app driven by `AppDelegate`.
public enum AutoHushApplication {
    @MainActor
    public static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run() // never returns; `delegate` stays alive for the app's lifetime
    }
}
