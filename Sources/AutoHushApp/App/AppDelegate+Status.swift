import AppKit
import AutoHushKit

// AppDelegate: what the menu and the windows show.
extension AppDelegate {
    /// Shows what the player session knows in the menu and Settings; with no
    /// player chosen, the status line asks for one.
    func showSession() {
        let state = session.state
        let sourcesChanged = state.activeSources != status.activeSources
        var shown = status
        shown.setHealth(state.health ?? .waitingForPlayer)
        shown.setActiveSources(state.activeSources)
        shown.playback = state.playback
        shown.detection = state.detection
        shown.controlError = state.controlError
        if shown != status { status = shown }
        // The monitoring recorded the apps it heard: Settings → Sound Sources lists them.
        if sourcesChanged { userSettings.appsSeenChanged() }
    }

    /// Quits and opens AutoHush again, as macOS's own "Quit & Reopen" does,
    /// handing over a pause it holds; `false` when the reopening couldn't be
    /// set up (it doesn't quit then, and says so).
    @discardableResult
    func reopen(
        openAfterExit: (URL) throws -> Void = { _ = try UpdateInstaller.openAfterExit($0) },
        terminate: () -> Void = { NSApp.terminate(nil) }
    ) -> Bool {
        do {
            try openAfterExit(Bundle.main.bundleURL)
        } catch {
            logger.error("Couldn’t reopen AutoHush: \(error)")
            tellFailure(PlayerAlerts.couldNotReopenAutoHush)
            return false
        }
        terminate()
        return true
    }

    /// Says that something the user asked for couldn't be done
    /// (`PlayerAlerts.couldNotReopenAutoHush` and the like), once no other
    /// alert is open.
    func tellFailure(_ failure: (title: String, message: String)) {
        InfoAlert.whenNoneOpen { InfoAlert.show(failure.title, failure.message, run: self.runAlert) }
    }
}
