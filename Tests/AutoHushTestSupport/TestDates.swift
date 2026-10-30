import Foundation

/// Dates in October 2026 on Madrid time, so tests don't depend on the Mac's
/// time zone.
package enum TestDates {
    package static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return calendar
    }()

    /// The day of October 2026 at the time given, e.g. `date(2, 15, 30)`.
    package static func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
}
