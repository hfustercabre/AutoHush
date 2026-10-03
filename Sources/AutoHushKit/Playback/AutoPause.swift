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

/// The "Turn Off For" choices of the menu, in menu order (the app has their text).
package enum AutoPauseSnooze: CaseIterable, Sendable {
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case twentyFourHours

    /// How long auto-pause stays off.
    package var duration: TimeInterval {
        switch self {
        case .fiveMinutes:     return 5 * 60
        case .fifteenMinutes:  return 15 * 60
        case .thirtyMinutes:   return 30 * 60
        case .oneHour:         return 60 * 60
        case .twentyFourHours: return 24 * 60 * 60
        }
    }

    /// When the snooze ends.
    package func endDate(from now: Date) -> Date {
        now.addingTimeInterval(duration)
    }
}
