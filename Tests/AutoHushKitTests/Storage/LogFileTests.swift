import Foundation
import Testing
@testable import AutoHushKit

@Suite("LogFile")
struct LogFileTests {
    /// A log in a folder of its own, at a clock the test moves.
    final class Scratch: @unchecked Sendable {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "LogFileTests-\(UUID().uuidString)/AutoHush.log")
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        func file() -> LogFile { LogFile(url: url, now: { [unowned self] in self.now }) }
        deinit { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    }

    private func entry(_ date: Date, _ message: String, level: LogLevel = .notice) -> LogEntry {
        LogEntry(date: date, level: level, category: "PlaybackArbiter", message: message)
    }

    @Test("entries are kept in order and read back as they were, line breaks and tabs included")
    func roundTrip() async {
        let scratch = Scratch()
        let log = scratch.file()
        let first = entry(scratch.now, "Spotify paused")
        let second = entry(scratch.now.addingTimeInterval(1), "two\nlines\twith a tab \\ and a backslash", level: .error)
        log.append(first)
        log.append(second)
        log.flush()
        let read = await log.entries(since: scratch.now.addingTimeInterval(-60))
        #expect(read.map(\.message) == [first.message, second.message])
        #expect(read.map(\.level) == [.notice, .error])
        #expect(abs(read[0].date.timeIntervalSince(first.date)) < 0.001)
        #expect(await log.entries(since: scratch.now.addingTimeInterval(0.5)).map(\.message) == [second.message])
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

    @Test("nothing older than 24 hours is kept: dropped as it opens, then as it's written to")
    func keepsADay() throws {
        let scratch = Scratch()
        let log = scratch.file()
        log.append(entry(scratch.now.addingTimeInterval(-LogFile.keptFor - 60), "too old"))
        log.append(entry(scratch.now.addingTimeInterval(-60), "recent"))
        log.flush()
        // Opened again later: the old line goes from the file itself.
        let reopened = scratch.file()
        reopened.flush()
        let text = try String(contentsOf: scratch.url, encoding: .utf8)
        #expect(!text.contains("too old"))
        #expect(text.contains("recent"))

        // An hour on, written to: the line now older than a day goes too.
        scratch.now = scratch.now.addingTimeInterval(LogFile.keptFor)
        reopened.append(entry(scratch.now, "new"))
        reopened.flush()
        let later = try String(contentsOf: scratch.url, encoding: .utf8)
        #expect(!later.contains("recent"))
        #expect(later.contains("new"))
    }

    @Test("whoever follows the log hears each entry appended, until it stops")
    func observers() {
        let scratch = Scratch()
        let log = scratch.file()
        final class Heard: @unchecked Sendable { var messages: [String] = [] }
        let heard = Heard()
        let token = log.observe { heard.messages.append($0.message) }
        log.append(entry(scratch.now, "one"))
        log.stopObserving(token)
        log.append(entry(scratch.now, "two"))
        log.flush()
        #expect(heard.messages == ["one"])
    }
}
