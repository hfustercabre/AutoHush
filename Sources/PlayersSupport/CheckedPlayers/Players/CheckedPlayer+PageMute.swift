import os
import WebAppPlayers

// CheckedPlayer: its page's mute in place of a pause.
extension CheckedPlayer {
    /// Not in AntiDot mode, which taps no sound: then it isn't listened to,
    /// its page can't mute it in place of a pause, and a mute under way is
    /// lifted.
    package nonisolated func allowTaps(_ allowed: Bool) {
        tapsAllowed.withLock { $0 = allowed }
        parts.page?.allowTaps(allowed)
        guard !allowed, let page = parts.page else { return }
        Task { await page.releaseMute() }
    }

    /// Its page's mute, standing for a pause.
    package func isMutedForPause() async -> Bool {
        await parts.page?.isMutedForPause() ?? false
    }

    /// Its page's (an ad its site won't pause, its button saying "Play"
    /// meanwhile).
    package func muteIfPlayingAnyway() async -> Bool {
        guard let page = parts.page else { return false }
        return await page.muteIfPlayingAnyway()
    }

    /// The Mac slept: AutoHush no longer holds the pause its page's mute
    /// stands for, lifted once the page is paused for real, or silent.
    package func forgetPause() async {
        await parts.page?.forgetPause()
    }
}
