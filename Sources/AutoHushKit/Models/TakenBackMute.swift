/// How the monitoring before held the pause a new monitoring takes back
/// (`MonitoringPipeline.start`), when that pause is a mute: a player found
/// playing as the new one starts is muted again at once, the same way,
/// before the one before lets go of its own mute, so the music isn't heard
/// until the apps are counted again (app-services-2, diff-app-1; see
/// `PlaybackArbiter.takeOverPause`).
package enum TakenBackMute: Sendable, Equatable {
    /// AutoHush's own tap muted it in place of the pause
    /// (`MonitoringStatusUpdate.mutedInstead`): the new monitoring's tap
    /// mutes it, found playing or not answering. `whileQuiet`: that mute
    /// was made as it was heard while it said it doesn't play
    /// (`mutesHeardWhileQuiet`), so it's muted again whatever it says
    /// (but not running), and its resume only unmutes it, as before (N1 of
    /// 11-27).
    case byTap(whileQuiet: Bool)
    /// It muted itself, and still does (an app added as Mute It Instead, a
    /// page's mute), as another player object of the same app (checked
    /// again): the new object's pause mutes it, found playing; found paused
    /// or stopped while heard (a page's ad), its own mute does.
    case byPlayer
}
