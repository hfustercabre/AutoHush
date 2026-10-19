import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("LogFile")
struct LogFileTests {
    /// A log in a folder of its own, at a clock the test moves.
    final class Scratch: Sendable {
        private let folder = TemporaryFolder("LogFileTests", create: false)
        private let clock = Locked(Date(timeIntervalSince1970: 1_800_000_000))
        var url: URL { folder.appending(path: "AutoHush.log") }
        var now: Date {
            get { clock.value }
            set { clock.value = newValue }
        }
        func file() -> LogFile { LogFile(url: url, now: { [clock] in clock.value }) }
    }

    private func entry(_ date: Date, _ message: String, level: LogLevel = .notice) -> LogEntry {
        LogEntry(date: date, level: level, category: "PlaybackArbiter", message: message)
    }

    @Test("entries are kept in order and read back as they were, line breaks, tabs and a closing carriage return included")
    func roundTrip() async {
        let scratch = Scratch()
        let log = scratch.file()
        let first = entry(scratch.now, "Spotify paused")
        // Left as it is, a closing "\r" would join the next line ("\r\n" is one Character).
        let second = entry(scratch.now.addingTimeInterval(1), "ends in a carriage return\r")
        let third = entry(scratch.now.addingTimeInterval(1), "two\nlines\twith a tab \\ and a backslash", level: .error)
        log.append(first)
        log.append(second)
        log.append(third)
        log.flush()
        let read = await log.entries(since: scratch.now.addingTimeInterval(-60))
        #expect(read.map(\.message) == [first.message, second.message, third.message])
        #expect(read.map(\.level) == [.notice, .notice, .error])
        #expect(abs(read[0].date.timeIntervalSince(first.date)) < 0.001)
        #expect(await log.entries(since: scratch.now.addingTimeInterval(0.5)).map(\.message) == [second.message, third.message])
    }

    @Test("past its most, the oldest lines go first: what's left is the newest that fit")
    func keepsMaxBytes() throws {
        let scratch = Scratch()
        // 25 lines of about a twentieth of the most each, a second apart.
        let long = String(repeating: "x", count: LogFile.maxBytes / 20)
        let lines = (0..<25).map { LogFile.line(for: entry(scratch.now.addingTimeInterval(Double($0 - 25)), "\($0) \(long)")) }
        try FileManager.default.createDirectory(at: scratch.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(lines.joined().utf8).write(to: scratch.url)
        scratch.file().flush() // trimmed as it opens
        var size = 0
        let fit = lines.reversed().prefix { line in
            size += line.utf8.count
            return size <= LogFile.maxBytes
        }
        #expect(fit.count < lines.count)
        let text = try String(contentsOf: scratch.url, encoding: .utf8)
        #expect(text.utf8.count <= LogFile.maxBytes)
        let keptNewest = text == fit.reversed().joined() // not compared in #expect, which would print 4 MB
        #expect(keptNewest)
    }

    @Test("nothing older than 24 hours is kept: dropped as it opens, then about hourly as it's written to; nor a line cut short")
    func keepsADay() throws {
        let scratch = Scratch()
        let log = scratch.file()
        let turningOld = entry(scratch.now.addingTimeInterval(-LogFile.keptFor + 20 * 60), "a day old in 20 minutes")
        let recent = entry(scratch.now.addingTimeInterval(-60), "recent")
        log.append(entry(scratch.now.addingTimeInterval(-LogFile.keptFor - 60), "too old"))
        log.append(turningOld)
        log.append(recent)
        log.flush()
        // A write cut short (the Mac lost power): a line that can't be read.
        let handle = try FileHandle(forWritingTo: scratch.url)
        _ = try handle.seekToEnd()
        try handle.write(contentsOf: Data((String(LogFile.line(for: entry(scratch.now, "cut short")).prefix(30)) + "\n").utf8))
        try handle.close()

        // Opened again: the old line and the one cut short go from the file itself.
        let opened = scratch.now
        let reopened = scratch.file()
        reopened.flush()
        #expect(try String(contentsOf: scratch.url, encoding: .utf8) == LogFile.line(for: turningOld) + LogFile.line(for: recent))

        // 40 minutes on, written to: the line a day old for 20 minutes stays, as old lines go only hourly.
        scratch.now = opened.addingTimeInterval(40 * 60)
        reopened.append(entry(scratch.now, "written 40 minutes on"))
        reopened.flush()
        #expect(try String(contentsOf: scratch.url, encoding: .utf8).contains(turningOld.message))

        // 61 minutes on, written to: it goes.
        scratch.now = opened.addingTimeInterval(61 * 60)
        reopened.append(entry(scratch.now, "written 61 minutes on"))
        reopened.flush()
        let later = try String(contentsOf: scratch.url, encoding: .utf8)
        #expect(!later.contains(turningOld.message))
        #expect(later.contains(recent.message) && later.contains("written 40 minutes on") && later.contains("written 61 minutes on"))
    }

    @Test("once the app's log is started, what's logged reaches it with the logger's category, debug lines aside")
    func loggedLines() async {
        let scratch = Scratch()
        let log = LogFile.start(at: scratch.url)
        #expect(LogFile.shared === log)
        let category = "LogFileTests-\(UUID().uuidString)" // other tests log meanwhile
        let logger = AutoHushLogger(category: category)
        logger.debug("a debug line")
        logger.info("an info line")
        logger.notice("a notice line")
        logger.error("an error line")
        log.flush()
        let logged = await log.entries(since: .distantPast).filter { $0.category == category }
        #expect(logged.map(\.level) == [.info, .notice, .error])
        #expect(logged.map(\.message) == ["an info line", "a notice line", "an error line"])
        LogFile.stop()
        log.flush() // what other tests logged meanwhile written before the folder goes
        withExtendedLifetime(scratch) {}
    }

    @Test("whoever follows the log hears each entry appended, until it stops")
    func observers() {
        let scratch = Scratch()
        let log = scratch.file()
        let heard = Locked<[String]>([])
        let token = log.observe { heard.append($0.message) }
        log.append(entry(scratch.now, "one"))
        log.stopObserving(token)
        log.append(entry(scratch.now, "two"))
        log.flush()
        #expect(heard.value == ["one"])
    }
}
