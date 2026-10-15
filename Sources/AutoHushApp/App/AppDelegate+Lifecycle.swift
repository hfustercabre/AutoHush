import AppKit
import AutoHushKit
import CheckedPlayers

// AppDelegate: launching, quitting, sleep and wake.
extension AppDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Now Playing, shown for a press while the user hid it, put back
        // should AutoHush have quit meanwhile.
        NowPlayingSetting.restoreIfLeft()
        // Shown while a window is open: the Mac's standard menus and keys.
        NSApp.mainMenu = MainMenu.make(about: { [weak self] in self?.openSettings(page: .about) },
                                       settings: { [weak self] in self?.openSettings() },
                                       find: { [weak self] in self?.find() },
                                       canFind: { [weak self] in self?.findTarget != nil })
        showStatusMenu()
        quitOnTerminationSignal()
        registerPlayerLaunchObserver()
        registerSleepObservers()
        followFocusAtLaunch()
        // Opened last, this copy is the one that runs: any opened before it
        // quits first, handing over a pause it held, so they never both pause
        // and resume the music.
        let otherInstances = otherInstances
        Task {
            let others = await otherInstances.quitAll()
            if !others.isEmpty { logger.notice("Quit \(others.count) other running AutoHush") }
            session.launch()
            if player == nil { showPlayerChooser() }
        }
        updates.noteLaunch()
        updates.scheduleAutomaticChecks()
    }

    /// Follows the Focus filter macOS reports now, which catches a Focus's
    /// start or end missed while AutoHush was quit (macOS doesn't open it for
    /// either). A failed read leaves Auto-Pause as it is.
    private func followFocusAtLaunch() {
        Task {
            do {
                focusAutoPause.followAtLaunch(try await AutoPauseFocusFilter.currentChoice())
            } catch {
                logger.error("Couldn't read the Focus filter: \(error)")
            }
        }
    }

    /// Puts AutoHush's menu in the menu bar: it shows the status, and its
    /// items go to the user's settings, the player session, the updates and
    /// AppDelegate.
    func showStatusMenu() {
        statusMenu = StatusMenuController(status: status, settings: userSettings, session: session,
                                          updates: updates, actions: self)
    }

    /// Waits (briefly) for a fade in progress to give the player its volume
    /// back, so quitting never leaves the music faded down.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // A pause AutoHush is holding is handed over (see `PlayerSession.quit`).
        guard let stopping = session.quit() else { return .terminateNow }
        var replied = false
        let reply: @MainActor () -> Void = {
            guard !replied else { return }
            replied = true
            sender.reply(toApplicationShouldTerminate: true)
        }
        Task { @MainActor in
            await stopping.value
            reply()
        }
        // Never hang the quit. A timer, not the main queue: it also fires when
        // the quit was asked for from inside a main-actor job.
        let fallback = Timer(timeInterval: 1, repeats: false) { _ in MainActor.assumeIsolated { reply() } }
        RunLoop.main.add(fallback, forMode: .common)
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        NowPlayingSetting.restoreIfLeft()
        unregisterPlayerLaunchObserver()
        sleepObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        sleepObservers = []
    }
}
