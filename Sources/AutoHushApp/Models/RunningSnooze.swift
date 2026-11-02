import Foundation
import AutoHushKit

/// A "Turn off for" that runs: when Auto-Pause turns back on, and the
/// duration chosen. The menu's bar marks that duration and says the time
/// left (U9c, the user's pick, 2026-11-02).
struct RunningSnooze: Equatable {
    /// When Auto-Pause turns back on.
    var end: Date
    /// The duration chosen; `nil` for a snooze an AutoHush before 1.3.0
    /// started, which kept only its end: no duration is marked then.
    var duration: AutoPauseSnooze?

    init(end: Date, duration: AutoPauseSnooze?) {
        self.end = end
        self.duration = duration
    }

    /// The snooze `setting` runs; `nil` while it's on, or off for good.
    init?(_ setting: AutoPauseSetting) {
        guard setting.isEnabled, let end = setting.snoozedUntil else { return nil }
        self.init(end: end, duration: setting.snooze)
    }

    /// The whole minutes left at `now`, rounded up: 1 in its last minute,
    /// 0 once it's over.
    func minutesLeft(at now: Date) -> Int {
        max(0, Int((end.timeIntervalSince(now) / 60).rounded(.up)))
    }

    /// When the minutes left next change after `now`, for the menu to read
    /// its clock again then; `nil` in the last minute, whose end turns
    /// Auto-Pause back on and takes the time left away with the snooze.
    func nextChange(after now: Date) -> Date? {
        let minutes = minutesLeft(at: now)
        guard minutes > 1 else { return nil }
        let next = end.addingTimeInterval(-Double(minutes - 1) * 60)
        // A rounding error must not ask for a moment that's gone.
        return next > now ? next : next.addingTimeInterval(60)
    }
}
