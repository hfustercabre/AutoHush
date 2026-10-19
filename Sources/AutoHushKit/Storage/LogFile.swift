import Foundation
import os

/// AutoHush's own log: a text file of the last 24 hours, the only place
/// AutoHush keeps what it logs (macOS gets it only for a live `log stream`:
/// see `AutoHushLogger`). Lines older than that go as it opens and then
/// about hourly, and the oldest go first past `maxBytes`, so it never holds
/// more than a day. Private values are left out of it.
///
/// One line per entry: the time (ISO 8601), the level, the category and the
/// message, separated by tabs, the message's line breaks and tabs escaped.
package final class LogFile: Sendable {
    /// How long a line is kept.
    package static let keptFor: TimeInterval = 24 * 60 * 60
    /// The most it holds, the oldest lines going first past it.
    package static let maxBytes = 4 * 1024 * 1024
    /// How often, at most, old lines are dropped while it's written to.
    static let trimInterval: TimeInterval = 60 * 60

    /// The log the app keeps, once it has started it; `nil` in tools and tests.
    package static var shared: LogFile? { current.withLock { $0 } }
    private static let current = OSAllocatedUnfairLock<LogFile?>(initialState: nil)

    /// Starts keeping the log at `url`: lines logged from now on go there.
    @discardableResult
    package static func start(at url: URL) -> LogFile {
        let file = LogFile(url: url)
        current.withLock { $0 = file }
        return file
    }

    /// Stops keeping it: lines logged from now on go nowhere (tests).
    package static func stop() {
        current.withLock { $0 = nil }
    }

    package let url: URL
    private let now: @Sendable () -> Date
    /// Writes, trims and reads, one at a time.
    private let queue = DispatchQueue(label: "AutoHush.LogFile", qos: .utility)
    /// When old lines were last dropped (read and set on `queue`; the lock
    /// lets the compiler check it).
    private let lastTrim = OSAllocatedUnfairLock<Date?>(initialState: nil)
    private let observers = OSAllocatedUnfairLock<[UUID: @Sendable (LogEntry) -> Void]>(initialState: [:])

    package init(url: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.url = url
        self.now = now
        queue.async { self.trim() }
    }

    /// Adds `entry`, and tells whoever follows the log once it's written.
    package func append(_ entry: LogEntry) {
        let following = observers.withLock { Array($0.values) }
        queue.async {
            self.write(Self.line(for: entry))
            for observer in following { observer(entry) }
            if self.lastTrim.withLock({ $0 }).map({ self.now().timeIntervalSince($0) >= Self.trimInterval }) ?? true { self.trim() }
        }
    }

    /// The lines kept since `date`, oldest first, read on the log's own
    /// queue: never on the caller's thread, as the file holds up to a day.
    package func entries(since date: Date) async -> [LogEntry] {
        await withCheckedContinuation { continuation in
            queue.async(qos: .userInitiated) {
                continuation.resume(returning: self.read().filter { $0.date >= date })
            }
        }
    }

    /// Calls `handler` with each entry appended from now on, on the log's
    /// queue once it's written, until `stopObserving` with the token
    /// returned. So an entry that `entries(since:)` reads was heard before
    /// it returned, and one it doesn't is heard after.
    package func observe(_ handler: @escaping @Sendable (LogEntry) -> Void) -> UUID {
        let token = UUID()
        observers.withLock { $0[token] = handler }
        return token
    }

    package func stopObserving(_ token: UUID) {
        observers.withLock { $0[token] = nil }
    }

    /// Returns once every line appended so far is written (tests).
    package func flush() {
        queue.sync {}
    }

    // MARK: - On the queue

    private func write(_ line: String) {
        let data = Data(line.utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url)
        }
    }

    private func read() -> [LogEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap(Self.entry(from:))
    }

    /// Drops the lines older than `keptFor`, and the oldest past `maxBytes`.
    private func trim() {
        let time = now()
        lastTrim.withLock { $0 = time }
        guard let data = try? Data(contentsOf: url) else { return }
        let cutoff = now().addingTimeInterval(-Self.keptFor)
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
            .filter { Self.entry(from: $0).map { $0.date >= cutoff } ?? false }
        var size = lines.reduce(0) { $0 + $1.utf8.count + 1 }
        var dropped = 0
        while size > Self.maxBytes, dropped < lines.count {
            size -= lines[dropped].utf8.count + 1
            dropped += 1
        }
        guard size != data.count else { return }
        try? Data(lines.dropFirst(dropped).map { $0 + "\n" }.joined().utf8).write(to: url, options: .atomic)
    }

    // MARK: - Lines

    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func line(for entry: LogEntry) -> String {
        [entry.date.formatted(dateStyle), entry.level.rawValue, escape(entry.category), escape(entry.message)]
            .joined(separator: "\t") + "\n"
    }

    static func entry(from line: Substring) -> LogEntry? {
        let fields = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
        guard fields.count == 4, let date = try? dateStyle.parse(String(fields[0])),
              let level = LogLevel(rawValue: String(fields[1])) else { return nil }
        return LogEntry(date: date, level: level, category: unescape(fields[2]), message: unescape(fields[3]))
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\t", with: "\\t")
    }

    private static func unescape(_ text: Substring) -> String {
        var result = ""
        var escaping = false
        for character in text {
            if escaping {
                switch character {
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                default: result.append(character)
                }
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }
        return result
    }
}
