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

/// The "Turn Off For" choices of the menu (the app has their text).
package enum AutoPauseSnooze: CaseIterable, Sendable {
    case fifteenMinutes
    case oneHour
    case untilTomorrow

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
}
