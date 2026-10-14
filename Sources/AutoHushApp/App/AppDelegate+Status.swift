import AppKit
import OSLog
import AutoHushKit

// AppDelegate: what the menu and the windows show.
extension AppDelegate {
    /// Shows what the player session knows in the menu and Settings; with no
    /// player chosen, the status line asks for one, among those listed.
    func showSession() {
        let state = session.state
        let sourcesChanged = state.activeSources != status.activeSources
        var shown = status
        shown.setHealth(state.health ?? .waitingForPlayer(among: shown.playerOptions))
        shown.setActiveSources(state.activeSources)
        shown.playback = state.playback
        shown.detection = state.detection
        shown.controlError = state.controlError
        if shown != status { status = shown }
        // The monitoring recorded the apps it heard: Settings → Apps lists them.
        if sourcesChanged { userSettings.appsSeenChanged() }
    }

    /// Quits and opens AutoHush again, as macOS's own "Quit & Reopen" does,
    /// handing over a pause it holds.
    func reopen(
        openAfterExit: (URL) throws -> Void = { _ = try UpdateInstaller.openAfterExit($0) },
        terminate: () -> Void = { NSApp.terminate(nil) }
    ) {
        do {
            try openAfterExit(Bundle.main.bundleURL)
        } catch {
            logger.error("Couldn't reopen AutoHush: \(error.localizedDescription, privacy: .public)")
            return
        }
        terminate()
    }
}
