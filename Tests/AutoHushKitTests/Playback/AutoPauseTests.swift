import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("AutoPause")
struct AutoPauseTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test("enabled without snooze is active; disabled is not")
    func enabledState() {
        let now = date(2, 12)
        #expect(AutoPauseSetting().isActive(at: now))
        #expect(!AutoPauseSetting(isEnabled: false).isActive(at: now))
    }

    @Test("a snooze is inactive until it ends")
    func snooze() {
        let setting = AutoPauseSetting(isEnabled: true, snoozedUntil: date(2, 13))
        #expect(!setting.isActive(at: date(2, 12, 59)))
        #expect(setting.isActive(at: date(2, 13)))
    }

    @Test("only expired snoozes are cleared")
    func clearingExpiredSnooze() {
        let setting = AutoPauseSetting(isEnabled: true, snoozedUntil: date(2, 13))
        #expect(setting.clearingExpiredSnooze(at: date(2, 12)) == setting)
        #expect(setting.clearingExpiredSnooze(at: date(2, 14)) == AutoPauseSetting(isEnabled: true, snoozedUntil: nil))
    }

    @Test("snooze end dates, in menu order")
    func endDates() {
        let now = date(2, 23, 30)
        #expect(AutoPauseSnooze.allCases.map { $0.endDate(from: now) } == [
            date(2, 23, 35), date(2, 23, 45), date(3, 0), date(3, 0, 30), date(3, 23, 30),
        ])
    }
}
