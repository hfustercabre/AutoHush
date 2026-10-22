import AppKit
import AutoHushKit
import CheckedPlayers

// AppDelegate: launching, quitting, sleep and wake.
extension AppDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        putBackWhatWasLeft()
        // Shown while a window is open: the Mac's standard menus and keys.
        NSApp.mainMenu = MainMenu.make(about: { [weak self] in self?.openSettings(page: .about) },
                                       settings: { [weak self] in self?.openSettings() },
                                       find: { [weak self] in self?.find() },
                                       canFind: { [weak self] in self?.findTarget != nil })
        showStatusMenu()
        quitOnTerminationSignal()
        registerPlayerLaunchObserver()
        ignoreVolumeSoundApps(NSWorkspace.shared.runningApplications.compactMap(\.audioSource))
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
            reopenAddAppIfAsked()
        }
        updates.noteLaunch()
        updates.scheduleAutomaticChecks()
    }

    /// At launch, what AutoHush changed for a moment and didn't put back,
    /// should it have quit or crashed meanwhile: Now Playing shown for a
    /// press while the user hid it, the Mac's output muted for a check, its
    /// volume lowered for the music (Level the volume).
    func putBackWhatWasLeft() {
        NowPlayingSetting.restoreIfLeft(defaults: nowPlayingDefaults, setting: nowPlayingSetting)
        addApp.putBackWhatWasLeft()
        volumeLeveler.restoreIfLeft()
    }

    /// Follows the Focus filter macOS reports now, which catches a Focus's
    /// start or end missed while AutoHush was quit (macOS doesn't open it for
    /// either). A failed read leaves Auto-Pause as it is.
    private func followFocusAtLaunch() {
        Task {
            do {
                focusAutoPause.followAtLaunch(try await AutoPauseFocusFilter.currentChoice())
            } catch {
                logger.error("Couldn’t read the Focus filter: \(error)")
            }
        }
    }

    /// Puts AutoHush's menu in the menu bar: it shows the status, and its
    /// items go to the user's settings, the player session, the updates and
    /// AppDelegate.
    func showStatusMenu() {
        statusMenu = StatusMenuController(status: status, settings: userSettings, session: session,
                                          updates: updates, actions: self, settingsModel: settingsModel)
    }

    /// Waits (briefly) for a fade in progress to give the player its volume
    /// back, so quitting never leaves the music faded down.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        shouldTerminate { sender.reply(toApplicationShouldTerminate: true) }
    }

    /// Quits at once when nothing runs. Otherwise the quit goes on (`reply`,
    /// once) when the player has its volume back and a pause AutoHush is
    /// holding is handed over (see `PlayerSession.quit`), or after `wait`.
    func shouldTerminate(wait: TimeInterval = 1, reply: @escaping @MainActor () -> Void) -> NSApplication.TerminateReply {
        guard let stopping = session.quit() else { return .terminateNow }
        var replied = false
        let replyOnce: @MainActor () -> Void = {
            guard !replied else { return }
            replied = true
            reply()
        }
        quitting = Task { @MainActor in
            await stopping.value
            replyOnce()
        }
        // Never hang the quit. A timer, not the main queue: it also fires when
        // the quit was asked for from inside a main-actor job.
        let fallback = Timer(timeInterval: wait, repeats: false) { _ in MainActor.assumeIsolated { replyOnce() } }
        RunLoop.main.add(fallback, forMode: .common)
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        NowPlayingSetting.restoreIfLeft(defaults: nowPlayingDefaults, setting: nowPlayingSetting)
        addApp.quit()
        // Even when the player's stop outlasted the quit's wait.
        volumeLeveler.restoreNow()
        // Its `log stream` would otherwise outlive AutoHush, until
        // mediaremoted next writes.
        CheckedPlayer.sharedReports.stop()
        unregisterPlayerLaunchObserver()
        sleepObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        sleepObservers = []
    }

    /// The Mac going to sleep and waking up, for the player session (see
    /// `PlayerSession.setAsleep`). The screens waking count as awake too, so
    /// a wake macOS didn't announce can't leave AutoHush deciding nothing.
    func registerSleepObservers() {
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers = [
            (NSWorkspace.willSleepNotification, true),
            (NSWorkspace.didWakeNotification, false),
            (NSWorkspace.screensDidWakeNotification, false),
        ].map { name, asleep in
            center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor [weak self] in self?.session.setAsleep(asleep) }
            }
        }
    }
}
