import AppKit
import SwiftUI
import AutoHushKit

/// The window shown before a check starts (W6): its Start runs the check.
@MainActor
final class CheckWarningWindowController: HostedWindowController {
    /// Whether Mission Control's desktop shortcuts are off, read again each
    /// time the warning or AutoHush comes back in front: the note goes once
    /// the user, sent to Keyboard settings by its button, turns them on (K3,
    /// the user, 2026-10-30).
    private let desktopShortcutsOff: @MainActor () -> Bool
    /// Whether the app's windows are all closed (`AddAppModel.appWindowsClosed`),
    /// read again as the desktop shortcuts are: the warning says what the
    /// check does then (W2 of 1.2.2, 2026-11-07).
    private let windowsClosed: @MainActor () -> Bool
    private let hosting: NSHostingController<CheckWarningView>
    private var observers: [any NSObjectProtocol] = []

    init(app: CheckableApp, muting: AddAppModel.CheckMuting, desktopShortcutsOff: @escaping @MainActor () -> Bool,
         windowsClosed: @escaping @MainActor () -> Bool = { false },
         openKeyboardSettings: @escaping () -> Void = { SystemSettingsPane.keyboard.open() },
         start: @escaping @MainActor () -> Void) {
        self.desktopShortcutsOff = desktopShortcutsOff
        self.windowsClosed = windowsClosed
        // The arrow keys' highlight, as in Settings.
        let keys = WindowKeys()
        let started = LaterAction(), cancel = LaterAction()
        let hosting = Self.sizedToFit(CheckWarningView(app: app, muting: muting, desktopShortcutsOff: desktopShortcutsOff(),
                                                       windowsClosed: windowsClosed(),
                                                       openKeyboardSettings: openKeyboardSettings, start: started.call,
                                                       cancel: cancel.call, keys: keys))
        self.hosting = hosting
        super.init(content: hosting, title: AddAppText.warningTitle(app.name), keys: keys)
        started.action = { [weak self] in
            self?.close()
            start()
        }
        cancel.action = { [weak self] in self?.close() }
        let center = NotificationCenter.default
        let readAgain: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.readAgain() }
        }
        observers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main, using: readAgain),
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main, using: readAgain),
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stopReading() }
            },
        ]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Whether the warning shows the note about the desktop shortcuts.
    var showsDesktopShortcutsNote: Bool { hosting.rootView.desktopShortcutsOff && !hosting.rootView.windowsClosed }
    /// Whether it says the app's windows are closed, so nothing is moved.
    var showsWindowsClosed: Bool { hosting.rootView.windowsClosed }

    private func readAgain() {
        let off = desktopShortcutsOff(), closed = windowsClosed()
        if off != hosting.rootView.desktopShortcutsOff { hosting.rootView.desktopShortcutsOff = off }
        if closed != hosting.rootView.windowsClosed { hosting.rootView.windowsClosed = closed }
    }

    /// Closed: each Continue… makes a new warning, so the closed one stops
    /// reading.
    private func stopReading() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }
}
