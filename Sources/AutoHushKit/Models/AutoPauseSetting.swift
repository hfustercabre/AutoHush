import Foundation

/// Whether AutoHush pauses the music automatically, as chosen by the user.
package struct AutoPauseSetting: Equatable, Sendable {
    package var isEnabled: Bool
    /// Temporarily off until this moment ("Turn Off For…").
    package var snoozedUntil: Date?
    /// The duration chosen for that snooze, which the menu marks while it
    /// runs; `nil` without a snooze, and for one an AutoHush before 1.3.0
    /// started, which kept only its end.
    package var snooze: AutoPauseSnooze?

    package init(isEnabled: Bool = true, snoozedUntil: Date? = nil, snooze: AutoPauseSnooze? = nil) {
        self.isEnabled = isEnabled
        self.snoozedUntil = snoozedUntil
        self.snooze = snoozedUntil == nil ? nil : snooze
    }

    /// Turned off for `snooze` from `now`, the duration kept with its end.
    package static func snoozed(_ snooze: AutoPauseSnooze, from now: Date) -> AutoPauseSetting {
        AutoPauseSetting(isEnabled: true, snoozedUntil: snooze.endDate(from: now), snooze: snooze)
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

/// What a Focus with AutoHush's filter noted of Auto-Pause, kept until the
/// Focus ends.
package struct FocusAutoPauseNote: Equatable, Sendable {
    /// How Auto-Pause stood before the first Focus.
    package var noted: AutoPauseSetting
    /// What the latest Focus set: on or off.
    package var applied: Bool

    package init(noted: AutoPauseSetting, applied: Bool) {
        self.noted = noted
        self.applied = applied
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

    /// The choice that lasts `duration` (as `Preferences` keeps it), if one does.
    package init?(duration: TimeInterval) {
        guard let snooze = Self.allCases.first(where: { $0.duration == duration }) else { return nil }
        self = snooze
    }
}
