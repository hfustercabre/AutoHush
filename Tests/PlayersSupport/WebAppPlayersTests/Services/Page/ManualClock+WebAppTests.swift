import Foundation
import AutoHushTestSupport

extension ManualClock {
    /// The web app tests' clock, from a date in 2026.
    static func webAppTests() -> ManualClock { ManualClock(start: Date(timeIntervalSinceReferenceDate: 800_000_000)) }
}
