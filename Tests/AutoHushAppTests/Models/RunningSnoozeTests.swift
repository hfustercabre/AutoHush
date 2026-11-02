import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit

@Suite("RunningSnooze")
struct RunningSnoozeTests {
    let end = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("only a snooze runs: not while Auto-Pause is on or off; one an older AutoHush started has no duration")
    func fromSetting() {
        #expect(RunningSnooze(AutoPauseSetting()) == nil)
        #expect(RunningSnooze(AutoPauseSetting(isEnabled: false)) == nil)
        #expect(RunningSnooze(AutoPauseSetting(isEnabled: true, snoozedUntil: end, snooze: .oneHour))
            == RunningSnooze(end: end, duration: .oneHour))
        #expect(RunningSnooze(AutoPauseSetting(isEnabled: true, snoozedUntil: end)) == RunningSnooze(end: end, duration: nil))
    }

    @Test("the minutes left are rounded up, 0 once it's over")
    func minutesLeft() {
        let snooze = RunningSnooze(end: end, duration: .fifteenMinutes)
        #expect(snooze.minutesLeft(at: end.addingTimeInterval(-15 * 60)) == 15)
        #expect(snooze.minutesLeft(at: end.addingTimeInterval(-11 * 60 - 30)) == 12)
        #expect(snooze.minutesLeft(at: end.addingTimeInterval(-1)) == 1)
        #expect(snooze.minutesLeft(at: end) == 0)
        #expect(snooze.minutesLeft(at: end.addingTimeInterval(60)) == 0)
    }

    @Test("the clock is read again as the minutes left change, not in the last minute")
    func nextChange() {
        let snooze = RunningSnooze(end: end, duration: .fifteenMinutes)
        #expect(snooze.nextChange(after: end.addingTimeInterval(-11 * 60 - 30)) == end.addingTimeInterval(-11 * 60))
        #expect(snooze.nextChange(after: end.addingTimeInterval(-12 * 60)) == end.addingTimeInterval(-11 * 60))
        #expect(snooze.nextChange(after: end.addingTimeInterval(-2 * 60)) == end.addingTimeInterval(-60))
        #expect(snooze.nextChange(after: end.addingTimeInterval(-59)) == nil)
        #expect(snooze.nextChange(after: end) == nil)
    }

    @Test("the time left says hours and minutes, never less than a minute")
    func timeLeft() {
        let snooze = RunningSnooze(end: end, duration: .twentyFourHours)
        #expect(snooze.timeLeft(at: end.addingTimeInterval(-12 * 60)) == SnoozeTimeLeft.text(minutes: 12))
        #expect(snooze.timeLeft(at: end.addingTimeInterval(-65 * 60)) == SnoozeTimeLeft.text(minutes: 65))
        #expect(snooze.timeLeft(at: end) == SnoozeTimeLeft.text(minutes: 1))
    }
}
