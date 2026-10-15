import AppKit
import AutoHushKit
import AutoHushPlayers
import WebAppPlayers

// AppDelegate: the apps added with Add an App, removed by the user.
extension AppDelegate {
    /// Asks, then removes the app added with `bundleID`: what its check found
    /// is forgotten, and it's no longer offered. The chosen player first lets
    /// go of what it turned on in its app (a mute, a switch), and none is
    /// chosen after it.
    func removeAddedAppAfterAsking(_ bundleID: String) {
        guard let option = status.playerOptions.first(where: { $0.bundleID == bundleID && $0.kind == .checkedApp }) else { return }
        let isChosen = player?.bundleID == bundleID
        // From the run loop: an alert run from a main-actor task would hold
        // up every other main-actor job until it closes.
        RunLoop.main.perform(inModes: [.common]) {
            MainActor.assumeIsolated {
                NSApp.activate()
                guard PlayerAlerts.remove(option.name, isChosen: isChosen).runModal() == .alertFirstButtonReturn else { return }
                self.removeAddedApp(option, wasChosen: isChosen)
            }
        }
    }

    private func removeAddedApp(_ option: PlayerOption, wasChosen: Bool) {
        if wasChosen, let removed = player, removed.bundleID == option.bundleID {
            setChosenPlayer(nil)
            Task { await removed.release() }
        }
        SupportedPlayers.checkedPlayers.forget(option.bundleID)
        ReopenChoices.setReopensAlways(option.bundleID, false)
        let kept = KeptCheckStore()
        if kept.load()?.app.bundleID == option.bundleID { kept.forget() }
        logger.notice("\(option.name, privacy: .public) removed from the players added with Add an App")
        refreshPlayerOptions()
    }
}
