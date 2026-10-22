import AppKit
import AutoHushKit
import CheckedPlayers

// AppDelegate: the apps added with Add an App, removed by the user.
extension AppDelegate {
    /// Asks, then removes the app added with `bundleID`: what its check found
    /// is forgotten, and it's no longer offered. The chosen player first lets
    /// go of what it turned on in its app (a mute, a switch), and none is
    /// chosen after it: the welcome window asks for another.
    func removeAddedAppAfterAsking(_ bundleID: String) {
        guard let option = status.playerOptions.first(where: { $0.bundleID == bundleID && $0.kind == .checkedApp }) else { return }
        let isChosen = player?.bundleID == bundleID
        InfoAlert.whenNoneOpen {
            guard self.runAlert(PlayerAlerts.remove(option.name, isChosen: isChosen)) == .alertFirstButtonReturn else { return }
            self.removeAddedApp(option, wasChosen: isChosen)
        }
    }

    /// Choosing no player doesn't release the one left (`PlayerSession.choose`),
    /// so the session releases it once, as it does a player left for another.
    /// One not chosen has nothing to let go of now: released when it was
    /// left, or once the pause AutoHush still holds in it is over.
    private func removeAddedApp(_ option: PlayerOption, wasChosen: Bool) {
        let removesChosen = wasChosen && player?.bundleID == option.bundleID
        if removesChosen, let removed = player {
            setChosenPlayer(nil)
            session.releaseLeft(removed)
        }
        checkedPlayers.forget(option.bundleID)
        ReopenChoices.setReopensAlways(option.bundleID, false, defaults: defaults)
        let kept = KeptCheckStore(defaults: defaults)
        if kept.load()?.app.bundleID == option.bundleID { kept.forget() }
        logger.notice("\(option.name, privacy: .public) removed from the players added with Add an App")
        if removesChosen {
            showPlayerChooser() // none is chosen now: asked for, as at launch
        } else {
            refreshPlayerOptions()
        }
    }
}
