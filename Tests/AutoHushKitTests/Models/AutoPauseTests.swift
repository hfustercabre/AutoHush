import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("AutoPause")
struct AutoPauseTests {
    @Test("enabled without snooze is active; disabled is not")
    func enabledState() {
        let now = TestDates.date(2, 12)
        #expect(AutoPauseSetting().isActive(at: now))
        #expect(!AutoPauseSetting(isEnabled: false).isActive(at: now))
    }

    @Test("a snooze is inactive until it ends")
    func snooze() {
        let setting = AutoPauseSetting(isEnabled: true, snoozedUntil: TestDates.date(2, 13))
        #expect(!setting.isActive(at: TestDates.date(2, 12, 59)))
        #expect(setting.isActive(at: TestDates.date(2, 13)))
    }

    @Test("only expired snoozes are cleared")
    func clearingExpiredSnooze() {
        let setting = AutoPauseSetting(isEnabled: true, snoozedUntil: TestDates.date(2, 13))
        #expect(setting.clearingExpiredSnooze(at: TestDates.date(2, 12)) == setting)
        #expect(setting.clearingExpiredSnooze(at: TestDates.date(2, 14)) == AutoPauseSetting(isEnabled: true, snoozedUntil: nil))
    }

    @Test("snooze end dates, in menu order")
    func endDates() {
        let now = TestDates.date(2, 23, 30)
        #expect(AutoPauseSnooze.allCases.map { $0.endDate(from: now) } == [
            TestDates.date(2, 23, 35), TestDates.date(2, 23, 45), TestDates.date(3, 0), TestDates.date(3, 0, 30), TestDates.date(3, 23, 30),
        ])
    }
}
