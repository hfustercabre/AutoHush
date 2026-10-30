import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("LogsModel", .waitsTimeLimit)
@MainActor
struct LogsModelTests {
    /// A log in memory; its reads can be held, as a long log's take a while.
    final class FakeLog: LogSource, @unchecked Sendable {
        var entries: [LogEntry] = []
        var handlers: [UUID: @Sendable (LogEntry) -> Void] = [:]
        var holdsReads = false
        var heldRead: CheckedContinuation<Void, Never>?
        func entries(since date: Date) async -> [LogEntry] {
            if holdsReads { await withCheckedContinuation { heldRead = $0 } }
            return entries.filter { $0.date >= date }
        }
        func releaseRead() {
            heldRead?.resume()
            heldRead = nil
        }
        func observe(_ handler: @escaping @Sendable (LogEntry) -> Void) -> UUID {
            let token = UUID()
            handlers[token] = handler
            return token
        }
        func stopObserving(_ token: UUID) { handlers[token] = nil }
        func log(_ entry: LogEntry) {
            entries.append(entry)
            hear(entry)
        }
        /// Heard, but not in the log yet: written after a read.
        func hear(_ entry: LogEntry) {
            handlers.values.forEach { $0(entry) }
        }
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(hoursAgo: Double, _ message: String, level: LogLevel = .notice, category: String = "PlayerSession") -> LogEntry {
        LogEntry(date: now.addingTimeInterval(-hoursAgo * 3600), level: level, category: category, message: message)
    }

    @Test("this launch, at most its last 24 hours; the last 24 hours, earlier launches too, never further")
    func ranges() async {
        let log = FakeLog()
        log.entries = [entry(hoursAgo: 30, "two days"), entry(hoursAgo: 20, "earlier launch"), entry(hoursAgo: 2, "this launch")]
        let model = LogsModel(source: log, launch: now.addingTimeInterval(-3 * 3600), now: { [now] in now })
        model.open()
        await TestWait.until { !model.isLoading }
        #expect(model.shown.map(\.message) == ["this launch"])
        model.range = .last24Hours
        await TestWait.until { !model.isLoading }
        #expect(model.shown.map(\.message) == ["earlier launch", "this launch"])

        // Open for more than a day: still only the last 24 hours.
        let longRunning = LogsModel(source: log, launch: now.addingTimeInterval(-40 * 3600), now: { [now] in now })
        longRunning.open()
        await TestWait.until { !longRunning.isLoading }
        #expect(longRunning.shown.map(\.message) == ["earlier launch", "this launch"])
        // The pop-up names the hours the log keeps.
        #expect(LogsModel.Range.last24Hours.title == "Last \(Int(LogFile.keptFor / 3600)) Hours")
    }

    @Test("the problems only, and a search over the lines and their areas")
    func filters() async {
        let log = FakeLog()
        log.entries = [entry(hoursAgo: 1, "Spotify paused"), entry(hoursAgo: 1, "Update check failed", level: .error, category: "Updates"),
                       entry(hoursAgo: 1, "Web app ready", category: "WebAppPlayer")]
        let model = LogsModel(source: log, launch: now.addingTimeInterval(-3600 * 2), now: { [now] in now })
        model.open()
        await TestWait.until { !model.isLoading }
        model.levels = .problems
        #expect(model.shown.map(\.message) == ["Update check failed"])
        model.levels = .all
        model.search = "web apps" // the area
        #expect(model.shown.map(\.message) == ["Web app ready"])
        model.search = "PAUSED"
        #expect(model.shown.map(\.message) == ["Spotify paused"])
        #expect(model.text.hasSuffix("Notice  Player  Spotify paused"))
        // A new line shows only if it matches too.
        log.log(entry(hoursAgo: 0, "Spotify paused again"))
        log.log(entry(hoursAgo: 0, "Update installed", category: "Updates"))
        await TestWait.until { model.entries.count == 5 }
        #expect(model.shown.map(\.message) == ["Spotify paused", "Spotify paused again"])
    }

    @Test("the search and the levels start again each time the window opens")
    func startsAgain() async {
        let model = LogsModel(source: FakeLog(), launch: now.addingTimeInterval(-3600), now: { [now] in now })
        model.open()
        model.search = "paused"
        model.levels = .problems
        model.close()
        model.open()
        #expect(model.search.isEmpty)
        #expect(model.levels == .all)
    }

    @Test("the log is read off the main thread: lines logged meanwhile show at once, then once each, after the read's")
    func readsMeanwhile() async {
        let log = FakeLog()
        log.entries = [entry(hoursAgo: 1, "before")]
        log.holdsReads = true
        let model = LogsModel(source: log, launch: now.addingTimeInterval(-7200), now: { [now] in now })
        model.open()
        await TestWait.until { log.heldRead != nil }
        #expect(model.isLoading)
        log.log(entry(hoursAgo: 0, "meanwhile")) // the read has it too
        log.hear(entry(hoursAgo: 0, "after the read")) // the read misses it
        await TestWait.until { model.entries.count == 2 }
        #expect(model.shown.map(\.message) == ["meanwhile", "after the read"])
        log.releaseRead()
        await TestWait.until { !model.isLoading }
        #expect(model.shown.map(\.message) == ["before", "meanwhile", "after the read"])
    }

    @Test("new lines show as they're logged, until the window closes; open for over a day, the lines older than 24 hours go")
    func follows() async {
        let log = FakeLog()
        let clock = ManualClock(start: now)
        let model = LogsModel(source: log, launch: now.addingTimeInterval(-3600), now: { clock.now })
        model.open()
        await TestWait.until { !model.isLoading }
        log.log(entry(hoursAgo: 0, "new"))
        await TestWait.until { model.entries.count == 1 }
        #expect(model.shown.map(\.message) == ["new"])
        clock.advance(by: 25 * 3600)
        log.log(entry(hoursAgo: -25, "a day later"))
        await TestWait.until { model.entries.map(\.message) == ["a day later"] }
        #expect(model.entries.map(\.message) == ["a day later"] && model.shown.map(\.message) == ["a day later"])
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
        // The engine's loggers about the player whose names don't say so.
        for category in ["PlayerMute", "OutputDisconnects", "VolumeLeveler", "PressCheck"] {
            #expect(LogsModel.area(of: category) == "Player", "\(category)")
        }
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
