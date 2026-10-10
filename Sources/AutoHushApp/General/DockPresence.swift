import AppKit

/// AutoHush is in the Dock (a regular app) while one of its windows is open:
/// Settings, the welcome, Add a Web App or learning window. Otherwise it's
/// only in the menu bar (an accessory app).
///
/// macOS brings back the last active app with a Dock icon when the user
/// returns to a desktop, and raises its windows: an accessory app's window
/// would fall behind them, though it was in front when the user left.
@MainActor
enum DockPresence {
    private static var closeObserver: NSObjectProtocol?
    /// The windows shown (`windowWillShow`) and not closed since.
    private static let shown = NSHashTable<NSWindow>.weakObjects()

    /// One of AutoHush's windows is about to show. Only AutoHush itself
    /// switches: a process that isn't an accessory app (tests) stays as
    /// it is.
    static func windowWillShow(_ window: NSWindow) {
        watchClosings()
        shown.add(window)
        if NSApp.activationPolicy() == .accessory { NSApp.setActivationPolicy(.regular) }
    }

    /// Shown and not closed since: open, even while macOS counts it as not
    /// visible (AutoHush hidden with ⌘H, or the window minimized).
    static func isShown(_ window: NSWindow) -> Bool {
        shown.contains(window)
    }

    /// Once its last window closes, back to the menu bar only; a window
    /// minimized in the Dock, or hidden with AutoHush, is still open.
    private static func watchClosings() {
        guard closeObserver == nil else { return }
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil,
                                                               queue: .main) { notification in
            let closing = notification.object as? NSWindow
            MainActor.assumeIsolated {
                if let closing { shown.remove(closing) }
                guard NSApp.activationPolicy() == .regular,
                      !NSApp.windows.contains(where: { $0 !== closing && $0.isOpen && isAppWindow($0) }) else { return }
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    /// A window the user works in: titled, not a panel (alerts, file
    /// panels) and not the menu's.
    static func isAppWindow(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.titled) && !(window is NSPanel)
    }
}
