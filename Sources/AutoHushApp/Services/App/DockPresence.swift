import AppKit

/// AutoHush is in the Dock (a regular app) while one of its windows is open:
/// Settings, the welcome, Add a Web App, Add an App, learning or logs
/// window. Otherwise it's only in the menu bar (an accessory app).
///
/// macOS brings back the last active app with a Dock icon when the user
/// returns to a desktop, and raises its windows: an accessory app's window
/// would fall behind them, though it was in front when the user left.
@MainActor
final class DockPresence {
    /// AutoHush's, on the app's activation policy and windows.
    static let shared = DockPresence()

    private let policy: () -> NSApplication.ActivationPolicy
    private let setPolicy: (NSApplication.ActivationPolicy) -> Void
    private let center: NotificationCenter
    private let windows: () -> [NSWindow]
    private var closeObserver: (any NSObjectProtocol)?
    /// The windows shown (`windowWillShow`) and not closed since.
    private let shown = NSHashTable<NSWindow>.weakObjects()

    /// Tests give a policy, a notification center and windows of their own.
    init(policy: @escaping () -> NSApplication.ActivationPolicy = { NSApp.activationPolicy() },
         setPolicy: @escaping (NSApplication.ActivationPolicy) -> Void = { _ = NSApp.setActivationPolicy($0) },
         center: NotificationCenter = .default,
         windows: @escaping () -> [NSWindow] = { NSApp.windows }) {
        self.policy = policy
        self.setPolicy = setPolicy
        self.center = center
        self.windows = windows
    }

    /// One of AutoHush's windows is about to show. Only AutoHush itself
    /// switches: a process that isn't an accessory app (tests) stays as
    /// it is.
    static func windowWillShow(_ window: NSWindow) { shared.windowWillShow(window) }

    /// Shown and not closed since: open, even while macOS counts it as not
    /// visible (AutoHush hidden with ⌘H, or the window minimized).
    static func isShown(_ window: NSWindow) -> Bool { shared.isShown(window) }

    func windowWillShow(_ window: NSWindow) {
        watchClosings()
        shown.add(window)
        if policy() == .accessory { setPolicy(.regular) }
    }

    func isShown(_ window: NSWindow) -> Bool {
        shown.contains(window)
    }

    /// Once its last window closes, back to the menu bar only; a window
    /// minimized in the Dock, or hidden with AutoHush, is still open.
    private func watchClosings() {
        guard closeObserver == nil else { return }
        closeObserver = center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] notification in
            let closing = notification.object as? NSWindow
            MainActor.assumeIsolated {
                guard let self else { return }
                if let closing { self.shown.remove(closing) }
                guard self.policy() == .regular,
                      !self.windows().contains(where: { $0 !== closing && self.isOpen($0) && Self.isAppWindow($0) }) else { return }
                self.setPolicy(.accessory)
            }
        }
    }

    /// As `NSWindow.isOpen`, by this one's windows shown.
    private func isOpen(_ window: NSWindow) -> Bool {
        window.isVisible || window.isMiniaturized || shown.contains(window)
    }

    /// A window the user works in: titled, not a panel (alerts, file
    /// panels) and not the menu's.
    static func isAppWindow(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.titled) && !(window is NSPanel)
    }
}
