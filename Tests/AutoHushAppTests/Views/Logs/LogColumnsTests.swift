import Foundation
import Testing
@testable import AutoHushApp
import AutoHushTestSupport

/// The logs window's columns, as wide as what they show.
@Suite("LogColumns", .waitsTimeLimit)
@MainActor
struct LogColumnsTests {
    @Test("the time column is measured again when the Mac's time zone changes: a longer offset isn't cut (K3-6 of 11-11)")
    func measuredAgainOnTimeZoneChange() async throws {
        let center = NotificationCenter()
        var zone = try #require(TimeZone(identifier: "UTC"))
        let measured = LogColumns.Measured(timeZone: { zone }, center: center)
        let utc = measured.columns.time
        zone = try #require(TimeZone(identifier: "Asia/Kathmandu")) // UTC+5:45, all year
        #expect(measured.columns.time == utc) // until macOS says it changed
        center.post(name: .NSSystemTimeZoneDidChange, object: nil)
        await TestWait.until { measured.columns.time > utc }
        #expect(measured.columns.time > utc)
    }
}
