import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("LogsModel")
@MainActor
struct LogsModelTests {
    /// A log in memory.
    final class FakeLog: LogSource, @unchecked Sendable {
        var entries: [LogEntry] = []
        var handlers: [UUID: @Sendable (LogEntry) -> Void] = [:]
        func entries(since date: Date) -> [LogEntry] { entries.filter { $0.date >= date } }
        func observe(_ handler: @escaping @Sendable (LogEntry) -> Void) -> UUID {
            let token = UUID()
            handlers[token] = handler
            return token
        }
        func stopObserving(_ token: UUID) { handlers[token] = nil }
        func log(_ entry: LogEntry) {
            entries.append(entry)
            handlers.values.forEach { $0(entry) }
        }
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(hoursAgo: Double, _ message: String, level: LogLevel = .notice, category: String = "PlayerSession") -> LogEntry {
        LogEntry(date: now.addingTimeInterval(-hoursAgo * 3600), level: level, category: category, message: message)
    }

    @Test("this launch, at most its last 24 hours; the last 24 hours, earlier launches too, never further")
    func ranges() {
        let log = FakeLog()
        log.entries = [entry(hoursAgo: 30, "two days"), entry(hoursAgo: 20, "earlier launch"), entry(hoursAgo: 2, "this launch")]
        let model = LogsModel(source: log, launch: now.addingTimeInterval(-3 * 3600), now: { [now] in now })
        model.open()
        #expect(model.shown.map(\.message) == ["this launch"])
        model.range = .last24Hours
        #expect(model.shown.map(\.message) == ["earlier launch", "this launch"])

        // Open for more than a day: still only the last 24 hours.
        let longRunning = LogsModel(source: log, launch: now.addingTimeInterval(-40 * 3600), now: { [now] in now })
        longRunning.open()
        #expect(longRunning.shown.map(\.message) == ["earlier launch", "this launch"])
    }

    @Test("the problems only, and a search over the lines and their areas")
    func filters() {
        let log = FakeLog()
        log.entries = [entry(hoursAgo: 1, "Spotify paused"), entry(hoursAgo: 1, "Update check failed", level: .error, category: "Updates"),
                       entry(hoursAgo: 1, "Web app ready", category: "WebAppPlayer")]
        let model = LogsModel(source: log, launch: now.addingTimeInterval(-3600 * 2), now: { [now] in now })
        model.open()
        model.levels = .problems
        #expect(model.shown.map(\.message) == ["Update check failed"])
        model.levels = .all
        model.search = "web apps" // the area
        #expect(model.shown.map(\.message) == ["Web app ready"])
        model.search = "PAUSED"
        #expect(model.shown.map(\.message) == ["Spotify paused"])
        #expect(model.text.hasSuffix("Notice  Player  Spotify paused"))
    }

    @Test("new lines show as they're logged, until the window closes")
    func follows() async {
        let log = FakeLog()
        let model = LogsModel(source: log, launch: now.addingTimeInterval(-3600), now: { [now] in now })
        model.open()
        log.log(entry(hoursAgo: 0, "new"))
        await TestWait.until { model.entries.count == 1 }
        #expect(model.shown.map(\.message) == ["new"])
        model.close()
        log.log(entry(hoursAgo: 0, "after closing"))
        #expect(log.handlers.isEmpty)
    }

    @Test("each logger's category belongs to an area of AutoHush")
    func areas() {
        #expect(LogsModel.area(of: "WebAppPlayer") == "Web Apps")
        #expect(LogsModel.area(of: "LearningSession") == "Web Apps")
        #expect(LogsModel.area(of: "PlaybackArbiter") == "Player")
        #expect(LogsModel.area(of: "AudioMonitor") == "Detection")
        #expect(LogsModel.area(of: "Updates") == "Updates")
        #expect(LogsModel.area(of: "Settings") == "Settings")
        #expect(LogsModel.area(of: "LaunchAtLogin") == "Settings")
        // Every area is listed, for the column's width.
        for category in ["WebAppPlayer", "PlaybackArbiter", "AudioMonitor", "Updates", "Settings", "AppDelegate"] {
            #expect(LogsModel.areas.contains(LogsModel.area(of: category)))
        }
        #expect(LogsModel.area(of: "AppDelegate") == "App")
    }

    @Test("each entry's time: the date, the 24-hour time and the offset from UTC then, never translated")
    func timestamps() throws {
        let date = Date(timeIntervalSince1970: 1_792_069_509) // 15 Oct 2026, 13:05:09 UTC
        #expect(LogsModel.timestamp(of: date, in: TimeZone(identifier: "UTC")!) == "15/10/2026 13:05:09 UTC")
        #expect(LogsModel.timestamp(of: date, in: TimeZone(identifier: "Europe/Madrid")!) == "15/10/2026 15:05:09 UTC+2")
        #expect(LogsModel.timestamp(of: date, in: TimeZone(identifier: "America/Sao_Paulo")!) == "15/10/2026 10:05:09 UTC-3")
        #expect(LogsModel.timestamp(of: date, in: TimeZone(identifier: "Asia/Kolkata")!) == "15/10/2026 18:35:09 UTC+5:30")
        // In winter, Madrid is an hour closer to UTC.
        let january = Date(timeIntervalSince1970: 1_799_845_509) // 13 Jan 2027, 13:05:09 UTC
        #expect(LogsModel.timestamp(of: january, in: TimeZone(identifier: "Europe/Madrid")!) == "13/01/2027 14:05:09 UTC+1")
    }
}
