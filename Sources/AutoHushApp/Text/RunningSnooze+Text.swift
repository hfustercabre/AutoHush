import Foundation

/// A running "Turn off for" in words: the menu's bar.
extension RunningSnooze {
    /// The time left at `now`, e.g. "12 min left" or "1 hr, 5 min left",
    /// beside the heading; never less than a minute.
    func timeLeft(at now: Date) -> String {
        let minutes = max(1, minutesLeft(at: now))
        let left = Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        return String(localized: "\(left) left",
                      comment: "Menu: beside “Turned off for”, how long until auto-pause turns back on; %@ is a duration in the user's language, e.g. “12 min” or “1 hr, 5 min”")
    }
}
