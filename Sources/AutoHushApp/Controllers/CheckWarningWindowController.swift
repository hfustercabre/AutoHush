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
    private let hosting: NSHostingController<CheckWarningView>
    private var observers: [any NSObjectProtocol] = []

    init(app: CheckableApp, muting: AddAppModel.CheckMuting, desktopShortcutsOff: @escaping @MainActor () -> Bool,
         openKeyboardSettings: @escaping () -> Void = { SystemSettingsPane.keyboard.open() },
         start: @escaping @MainActor () -> Void) {
        self.desktopShortcutsOff = desktopShortcutsOff
        let hosting = Self.sizedToFit(CheckWarningView(app: app, muting: muting, desktopShortcutsOff: desktopShortcutsOff(),
                                                       openKeyboardSettings: openKeyboardSettings, start: {}, cancel: {}))
        self.hosting = hosting
        super.init(content: hosting, title: AddAppText.warningTitle(app.name))
        hosting.rootView = CheckWarningView(app: app, muting: muting, desktopShortcutsOff: hosting.rootView.desktopShortcutsOff,
                                            openKeyboardSettings: openKeyboardSettings, start: { [weak self] in
            self?.close()
            start()
        }, cancel: { [weak self] in self?.close() })
        let center = NotificationCenter.default
        let readAgain: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.readDesktopShortcuts() }
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
    var showsDesktopShortcutsNote: Bool { hosting.rootView.desktopShortcutsOff }

    private func readDesktopShortcuts() {
        let off = desktopShortcutsOff()
        guard off != hosting.rootView.desktopShortcutsOff else { return }
        hosting.rootView.desktopShortcutsOff = off
    }

    /// Closed: each Continue… makes a new warning, so the closed one stops
    /// reading.
    private func stopReading() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }
}
