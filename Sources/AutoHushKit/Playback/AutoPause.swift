import Foundation

/// Whether AutoHush pauses the music automatically, as chosen by the user.
package struct AutoPauseSetting: Equatable, Sendable {
    package var isEnabled: Bool
    /// Temporarily off until this moment ("Turn Off For…").
    package var snoozedUntil: Date?

    package init(isEnabled: Bool = true, snoozedUntil: Date? = nil) {
        self.isEnabled = isEnabled
        self.snoozedUntil = snoozedUntil
    }

    package func isActive(at now: Date) -> Bool {
        guard isEnabled else { return false }
        guard let snoozedUntil else { return true }
        return now >= snoozedUntil
    }

    /// The same setting with an expired snooze removed.
    package func clearingExpiredSnooze(at now: Date) -> AutoPauseSetting {
        guard let snoozedUntil, now >= snoozedUntil else { return self }
        return AutoPauseSetting(isEnabled: isEnabled, snoozedUntil: nil)
    }
}

/// The "Turn Off For" choices of the menu.
package enum AutoPauseSnooze: CaseIterable, Sendable {
    case fifteenMinutes
    case oneHour
    case untilTomorrow

    package var title: String {
        switch self {
        case .fifteenMinutes: return "15 Minutes"
        case .oneHour:        return "1 Hour"
        case .untilTomorrow:  return "Until Tomorrow"
        }
    }

    /// When the snooze ends; "until tomorrow" means tomorrow at 8:00.
    package func endDate(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .fifteenMinutes:
            return now.addingTimeInterval(15 * 60)
        case .oneHour:
            return now.addingTimeInterval(60 * 60)
        case .untilTomorrow:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow)!
        }
    }

    /// "15:30" today, "tomorrow 8:00", otherwise weekday and time.
    package static func describeEnd(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = calendar.timeZone
        let time = date.formatted(style)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow \(time)"
        }
        var weekday = Date.FormatStyle().weekday(.wide)
        weekday.timeZone = calendar.timeZone
        return "\(date.formatted(weekday)) \(time)"
    }
}
