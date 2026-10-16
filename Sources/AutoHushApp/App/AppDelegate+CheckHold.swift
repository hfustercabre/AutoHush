import Foundation

// AppDelegate: holding the media player while Add an App checks an app.
extension AppDelegate {
    /// Add an App's check (`checkStarted`, `checkEnded`): for about three
    /// minutes it plays the app it checks and pauses and plays it again and
    /// again, judging it partly by Now Playing. AutoHush pausing and resuming
    /// the media player in its gaps would fade it in and out, make it the
    /// Now Playing app, and press the menu bar's Now Playing item along with
    /// the check when the player is controlled there. So while it runs,
    /// AutoHush resumes nothing: a player it paused stays paused until the
    /// check ends, then comes back as usual (`PlayerSession.holdResumes`).
    func holdsPlayerForCheck(_ held: Bool) {
        guard held != session.resumesHeld else { return }
        logger.info("Add an App’s check \(held ? "runs: AutoHush resumes nothing until it ends" : "ended: AutoHush resumes as usual", privacy: .public)")
        session.holdResumes(held)
        status.playerHeldForCheck = held
    }
}
