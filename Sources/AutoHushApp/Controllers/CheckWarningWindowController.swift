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
    /// Looks at the app's windows now (`AddAppModel.lookAtWindows`), not at
    /// the watch's next look, up to 2 s later: as the warning comes up and
    /// comes back in front, and at its Start, which, if they changed, shows
    /// what the check will then do instead of starting the other (F-6, the
    /// code check of 2026-11-07).
    private let lookAtWindows: @MainActor () async -> Void
    private let hosting: NSHostingController<CheckWarningView>
    private var observers: [any NSObjectProtocol] = []
    /// Its Start looks at the app's windows before the check starts.
    private var isStarting = false
    /// Closed (Cancel, or by AutoHush): its Start no longer starts the check.
    private var isClosed = false

    init(app: CheckableApp, muting: AddAppModel.CheckMuting, desktopShortcutsOff: @escaping @MainActor () -> Bool,
         windowsClosed: @escaping @MainActor () -> Bool = { false },
         lookAtWindows: @escaping @MainActor () async -> Void = {},
         openKeyboardSettings: @escaping () -> Void = { SystemSettingsPane.keyboard.open() },
         start: @escaping @MainActor () -> Void) {
        self.desktopShortcutsOff = desktopShortcutsOff
        self.windowsClosed = windowsClosed
        self.lookAtWindows = lookAtWindows
        // The arrow keys' highlight, as in Settings.
        let keys = WindowKeys()
        let started = LaterAction(), cancel = LaterAction()
        let hosting = Self.sizedToFit(CheckWarningView(app: app, muting: muting, desktopShortcutsOff: desktopShortcutsOff(),
                                                       windowsClosed: windowsClosed(),
                                                       openKeyboardSettings: openKeyboardSettings, start: started.call,
                                                       cancel: cancel.call, keys: keys))
        self.hosting = hosting
        super.init(content: hosting, title: AddAppText.warningTitle(app.name), keys: keys)
        started.action = { [weak self] in self?.startAfterLook(start) }
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
        readWindowsAgain()
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
        readWindowsAgain()
    }

    /// The app's windows looked at now, then read again.
    private func readWindowsAgain() {
        Task { [weak self] in
            await self?.lookAtWindows()
            self?.showWindowsClosed()
        }
    }

    /// Shows whether the app's windows are all closed, as last looked at:
    /// `true` if that changed what it said.
    @discardableResult
    private func showWindowsClosed() -> Bool {
        let closed = windowsClosed()
        guard closed != hosting.rootView.windowsClosed else { return false }
        hosting.rootView.windowsClosed = closed
        return true
    }

    /// Start: the app's windows looked at first. As the warning said, it
    /// closes and the check starts; changed, it says what the check will
    /// do now, for another Start. Nothing starts once it's closed meanwhile
    /// (Cancel, or the app quit).
    private func startAfterLook(_ start: @escaping @MainActor () -> Void) {
        guard !isStarting else { return }
        isStarting = true
        Task { [weak self] in
            guard let self else { return }
            await self.lookAtWindows()
            self.isStarting = false
            guard !self.isClosed, !self.showWindowsClosed() else { return }
            self.close()
            start()
        }
    }

    /// Closed: each Continue… makes a new warning, so the closed one stops
    /// reading.
    private func stopReading() {
        isClosed = true
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }
}
