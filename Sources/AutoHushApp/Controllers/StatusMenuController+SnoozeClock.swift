import Foundation

// StatusMenuController: the clock behind the snooze bar's time left, read
// as the menu opens and again each time the minutes left change, only
// while it's open and a "Turn off for" runs (U9c, 2026-11-02).
extension StatusMenuController {
    /// Reads the clock for the time left, and sets the timer that reads it
    /// again as its minutes change: none while the menu is closed or no
    /// snooze runs.
    func followSnoozeClock() {
        stopSnoozeClock()
        let date = now()
        model.now = date
        guard isMenuOpen, let next = status.snooze?.nextChange(after: date) else { return }
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.followSnoozeClock() }
        }
        RunLoop.main.add(timer, forMode: .common)
        setSnoozeClock(timer)
    }

    /// Stops reading it (`close`).
    func stopSnoozeClock() {
        snoozeClock?.invalidate()
        setSnoozeClock(nil)
    }
}
