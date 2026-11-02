import AppKit
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

// The "Turn off for" bar (U9c, 2026-11-02): hidden while Auto-Pause is off,
// the duration running marked with the time left while it's turned off for
// a while, read again as its minutes change while the menu is open.
extension StatusMenuControllerTests {
    /// Ready, Auto-Pause turned off for 15 minutes from `start`.
    func snoozedStatus(from start: Date, duration: AutoPauseSnooze? = .fifteenMinutes) -> AppStatus {
        var status = readyStatus()
        status.autoPause = .snoozed("until 15:42")
        status.snooze = RunningSnooze(end: start.addingTimeInterval(15 * 60), duration: duration)
        return status
    }

    @Test("Turn off for shows while Auto-Pause is on or turned off for a while, never while it's off")
    func snoozeBarHiddenWhileOff() {
        let sut = makeController()
        defer { sut.remove() }
        sut.status = readyStatus()
        reopen(sut)
        #expect(parts(sut) == ["card", "snooze", "ignoredApps", "toolbar"])

        var off = readyStatus()
        off.autoPause = .off
        sut.status = off
        #expect(parts(sut) == ["card", "ignoredApps", "toolbar"]) // at once, the menu open

        sut.status = snoozedStatus(from: Date())
        #expect(parts(sut) == ["card", "snooze", "ignoredApps", "toolbar"])
    }

    @Test("while on, Turn off for marks nothing; turned off for a while, the duration running is selected under Turned off for, with the time left")
    func snoozeBarStates() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let sut = makeController()
        defer { sut.remove() }
        sut.now = { start.addingTimeInterval(3 * 60 + 30) } // 11.5 minutes left
        sut.status = readyStatus()
        reopen(sut)
        #expect(sut.model.snoozeHeading == "Turn off for")
        #expect(sut.model.runningSnoozeDuration == nil && sut.model.snoozeTimeLeft == nil)

        sut.status = snoozedStatus(from: start)
        reopen(sut)
        #expect(sut.model.snoozeHeading == "Turned off for")
        #expect(sut.model.runningSnoozeDuration == .fifteenMinutes)
        #expect(sut.model.snoozeTimeLeft == SnoozeTimeLeft.text(minutes: 12))
    }

    @Test("a snooze an older AutoHush started, its duration unknown, selects none but says the heading and the time left")
    func snoozeBarWithoutDuration() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let sut = makeController()
        defer { sut.remove() }
        sut.now = { start }
        sut.status = snoozedStatus(from: start, duration: nil)
        reopen(sut)
        #expect(sut.model.snoozeHeading == "Turned off for")
        #expect(sut.model.runningSnoozeDuration == nil)
        #expect(sut.model.snoozeTimeLeft == SnoozeTimeLeft.text(minutes: 15))
    }

    @Test("the time left is read as the menu opens, again as its minutes change while open, and not at all once it's closed or the snooze is over")
    func snoozeClock() throws {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var clock = start.addingTimeInterval(30)
        let sut = makeController()
        defer { sut.remove() }
        sut.now = { clock }
        sut.status = readyStatus()
        reopen(sut)
        #expect(sut.snoozeClock == nil) // on: nothing to count down

        sut.status = snoozedStatus(from: start) // turned off with the menu open
        #expect(sut.model.now == clock)
        let timer = try #require(sut.snoozeClock)
        #expect(timer.fireDate == start.addingTimeInterval(60)) // 15 min left becomes 14
        #expect(sut.model.snoozeTimeLeft == SnoozeTimeLeft.text(minutes: 15))

        clock = start.addingTimeInterval(60)
        timer.fire()
        #expect(sut.model.snoozeTimeLeft == SnoozeTimeLeft.text(minutes: 14))
        #expect(sut.snoozeClock?.fireDate == start.addingTimeInterval(120))

        sut.close()
        #expect(sut.snoozeClock == nil)

        clock = start.addingTimeInterval(14 * 60 + 30) // the last minute: its end turns Auto-Pause on
        sut.open(showsPanel: false)
        #expect(sut.model.snoozeTimeLeft == SnoozeTimeLeft.text(minutes: 1))
        #expect(sut.snoozeClock == nil)
    }

    @Test("a click on another duration while one runs starts the one clicked")
    func snoozeAgain() async {
        let sut = makeController()
        defer { sut.remove() }
        settings.snooze(.fifteenMinutes)
        sut.model.perform(.snooze(.oneHour)) // as the bar sends it
        await TestWait.until { settings.state.snooze?.duration == .oneHour }
        #expect(settings.autoPauseSetting.snooze == .oneHour)
    }
}
