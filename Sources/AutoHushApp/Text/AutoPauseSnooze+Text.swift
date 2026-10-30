import Foundation
import AutoHushKit

/// Turning Auto-Pause off for a while, in words: the menu's durations and
/// when the snooze ends.
extension AutoPauseSnooze {
    /// The duration on its button in the menu, e.g. "15 min" or "1 hr", in
    /// the user's language.
    var shortTitle: String {
        Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    /// The choice in full, e.g. "15 Minutes", as VoiceOver reads it.
    var title: String {
        switch self {
        case .fiveMinutes:
            return String(localized: "5 Minutes", comment: "In the menu: turn auto-pause off for 5 minutes")
        case .fifteenMinutes:
            return String(localized: "15 Minutes", comment: "In the menu: turn auto-pause off for 15 minutes")
        case .thirtyMinutes:
            return String(localized: "30 Minutes", comment: "In the menu: turn auto-pause off for 30 minutes")
        case .oneHour:
            return String(localized: "1 Hour", comment: "In the menu: turn auto-pause off for 1 hour")
        case .twentyFourHours:
            return String(localized: "24 Hours", comment: "In the menu: turn auto-pause off for 24 hours")
        }
    }

    /// When the snooze ends, with its preposition so that each language can
    /// place it in a sentence: "until 15:30" today, otherwise "until tomorrow
    /// 8:00" (a snooze lasts 24 hours at most).
    static func describeEnd(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = calendar.timeZone
        let time = date.formatted(style)
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "until \(time)", comment: "When auto-pause turns back on today; %@ is a time")
        }
        return String(localized: "until tomorrow \(time)", comment: "When auto-pause turns back on; %@ is a time")
    }
}
