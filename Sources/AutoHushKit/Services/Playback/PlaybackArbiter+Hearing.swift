import Foundation

// PlaybackArbiter: the menu's listen to the player, so it says at once
// whether a player that says it plays here is heard (Playing silently).
extension PlaybackArbiter {
    /// Listens to the player when the menu opens, so it says at once whether
    /// a player that says it plays here is heard (the user, 2026-10-24). The
    /// listen (a tap of its own, half a second) runs in a task of its own,
    /// one at a time, so the pipeline's next command doesn't wait for it.
    func checkPlayerHeard() {
        guard heardCheck == nil else { return }
        heardCheck = Task { [weak self] in
            await self?.listenForMenu()
            await self?.heardCheckEnded()
        }
    }

    private func heardCheckEnded() { heardCheck = nil }

    private func listenForMenu() async {
        guard !isShutDown, playerState == .playing, playsLocally, !pausedByUs, !isFadingOut else { return }
        let heard: Bool
        switch await hearsPlayer(true, nil) {
        case .heard: heard = true
        case .silent: heard = false
        case .measuring, .unknown: return
        }
        guard !isShutDown, playerState == .playing, playsLocally, !pausedByUs, playsSilently == heard else { return }
        if !heard { silentWithoutState = !(await player.statesItself()) }
        playsSilently = !heard
        publishPlaybackState()
    }
}
