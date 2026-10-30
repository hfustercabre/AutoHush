import AppKit

// AppDelegate: the updates.
extension AppDelegate {
    /// Quits from the run loop, not from inside a main-actor job (the install's
    /// task, a signal handler): quitting waits for main-actor work (restoring
    /// the volume), which can't run while a main-actor job is still under way.
    /// After an update, so that the installed one opens; a pause AutoHush is
    /// holding is handed over (see `applicationShouldTerminate`).
    func quitFromRunLoop() {
        RunLoop.main.perform { MainActor.assumeIsolated { NSApp.terminate(nil) } }
    }

    /// Quits normally on SIGTERM (from an AutoHush opened after this one,
    /// `kill`, or the system) instead of stopping at once, so the volume is
    /// restored and a pause handed over. An alert open (an update's, say)
    /// closes first: the quit waits for it otherwise, and an AutoHush opened
    /// after this one forces it after a few seconds.
    func quitOnTerminationSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.terminationSignalArrived() }
        }
        source.resume()
        terminationSignal = source
    }

    /// What SIGTERM does: closes the alert open (`modal`), then quits from
    /// the run loop (`quit`; tests give their own).
    func terminationSignalArrived(modal: NSWindow? = NSApp.modalWindow, abortModal: () -> Void = { NSApp.abortModal() },
                                  quit: (() -> Void)? = nil) {
        if modal != nil { abortModal() }
        if let quit { quit() } else { quitFromRunLoop() }
    }

    /// A moment when AutoHush can restart for an update unnoticed: it isn't
    /// holding the music paused (the new version would take that pause over,
    /// but there is no need to rely on it), and none of its menus, windows or
    /// alerts is open.
    var isQuietMoment: Bool {
        !session.isHoldingPause
            && statusMenu?.isMenuOpen != true
            && !hasOpenWindow()
    }
}
