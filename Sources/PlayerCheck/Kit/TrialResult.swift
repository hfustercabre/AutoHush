/// How a trial went: it paused and played again, it only paused, or it
/// didn't pause.
package enum TrialResult: Sendable { case worked, pausedOnly, didNotPause }
