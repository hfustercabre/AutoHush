import AppKit
import Observation
import AutoHushKit

/// Where the logs window reads AutoHush's log: `LogFile`; tests stand in.
protocol LogSource: AnyObject, Sendable {
    func entries(since date: Date) async -> [LogEntry]
    func observe(_ handler: @escaping @Sendable (LogEntry) -> Void) -> UUID
    func stopObserving(_ token: UUID)
}

extension LogFile: LogSource {}

/// What the logs window shows: AutoHush's log since this launch, or over
/// the last 24 hours (earlier launches too), never further back; all of it
/// or only the problems, narrowed by a search, new lines added as they come.
/// The log is read off the main thread; what's shown stays meanwhile.
@MainActor
@Observable
final class LogsModel {
    enum Range: CaseIterable, Hashable {
        /// Since AutoHush opened, at most its last 24 hours.
        case thisLaunch
        /// The last 24 hours, earlier launches included.
        case last24Hours
    }

    enum Levels: CaseIterable, Hashable {
        case all
        /// Errors.
        case problems
    }

    var range = Range.thisLaunch {
        didSet { if range != oldValue { reload() } }
    }
    var levels = Levels.all {
        didSet { if levels != oldValue { refilter() } }
    }
    var search = "" {
        didSet { if search != oldValue { refilter() } }
    }
    /// The list scrolls to each new line as it comes.
    var followsNewEntries = true
    private(set) var entries: [LogEntry] = []
    /// The lines shown: the problems only when asked, matching the search.
    /// Filtered again only when the filters change; a new line is added.
    private(set) var shown: [LogEntry] = []
    /// The log is being read.
    private(set) var isLoading = false

    /// When this copy of AutoHush opened.
    @ObservationIgnored let launch: Date
    @ObservationIgnored private let source: (any LogSource)?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var observation: UUID?
    /// Counts the reads, so only the last one started is shown.
    @ObservationIgnored private var reads = 0
    /// Lines heard while the log is read: kept, unless the read has them.
    @ObservationIgnored private var heardMeanwhile: [LogEntry] = []

    init(source: (any LogSource)? = LogFile.shared, launch: Date = LogsModel.launchDate, now: @escaping () -> Date = { Date() }) {
        self.source = source
        self.launch = launch
        self.now = now
    }

    /// When this copy opened.
    static var launchDate: Date { NSRunningApplication.current.launchDate ?? Date() }

    /// The oldest moment shown: 24 hours ago, or this launch when later.
    var since: Date {
        let dayAgo = now().addingTimeInterval(-LogFile.keptFor)
        return range == .thisLaunch ? max(launch, dayAgo) : dayAgo
    }

    /// The window opens: the search empty and every level again, its
    /// lines, then each new one as it's logged.
    func open() {
        search = ""
        levels = .all
        if observation == nil, let source {
            observation = source.observe { [weak self] entry in
                Task { @MainActor in self?.append(entry) }
            }
        }
        reload()
    }

    /// The window closes: no more following.
    func close() {
        if let observation { source?.stopObserving(observation) }
        observation = nil
    }

    /// Reads the lines since `since` off the main thread, then shows them
    /// with those logged meanwhile that the read missed.
    func reload() {
        guard let source else { return }
        let since = since
        if !isLoading { heardMeanwhile = [] }
        reads += 1
        let read = reads
        isLoading = true
        Task {
            let lines = await source.entries(since: since)
            guard read == reads else { return } // a later read shows instead
            let missed = heardMeanwhile.filter { heard in
                heard.date >= since && !lines.reversed().contains { $0.isSameLine(as: heard) }
            }
            entries = lines + missed
            heardMeanwhile = []
            isLoading = false
            refilter()
        }
    }

    /// A line just logged; those older than `since` go meanwhile.
    func append(_ entry: LogEntry) {
        let since = since
        guard entry.date >= since else { return }
        if isLoading { heardMeanwhile.append(entry) }
        if let first = entries.first, first.date < since {
            entries.removeAll { $0.date < since }
            shown.removeAll { $0.date < since }
        }
        entries.append(entry)
        if matches(entry, query: query) { shown.append(entry) }
    }

    private var query: String { search.trimmingCharacters(in: .whitespaces) }

    private func refilter() {
        let query = query
        shown = entries.filter { matches($0, query: query) }
    }

    private func matches(_ entry: LogEntry, query: String) -> Bool {
        (levels == .all || entry.level.isProblem)
            && (query.isEmpty || entry.message.localizedStandardContains(query)
                || Self.area(of: entry.category).localizedStandardContains(query))
    }

    /// The lines shown, as text to copy or save: the date and time, the
    /// level, the area and the line.
    var text: String {
        shown.map { entry in
            "\(Self.timestamp(of: entry.date))  \(entry.level.rawValue.capitalized)  \(Self.area(of: entry.category))  \(entry.message)"
        }.joined(separator: "\n")
    }

    /// When an entry was logged, as the window and its copies say it: the
    /// date, the 24-hour time and the time zone's offset from UTC then, e.g.
    /// "15/10/2026 13:05:09 UTC+2". Never translated, as the log isn't.
    static func timestamp(of date: Date, in timeZone: TimeZone = .current) -> String {
        let style = Date.VerbatimFormatStyle(
            format: "\(day: .twoDigits)/\(month: .twoDigits)/\(year: .defaultDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)",
            locale: Locale(identifier: "en_US_POSIX"), timeZone: timeZone, calendar: Calendar(identifier: .gregorian))
        return "\(date.formatted(style)) \(utcOffset(seconds: timeZone.secondsFromGMT(for: date)))"
    }

    /// An offset from UTC: "UTC", "UTC+2", "UTC-3", "UTC+5:30".
    static func utcOffset(seconds: Int) -> String {
        guard seconds != 0 else { return "UTC" }
        let minutes = abs(seconds) / 60
        let rest = minutes % 60 == 0 ? "" : ":" + String(format: "%02d", minutes % 60)
        return "UTC\(seconds < 0 ? "-" : "+")\(minutes / 60)\(rest)"
    }

    /// The part of AutoHush a logger's category belongs to, as the window
    /// shows it: in English, as the lines themselves are.
    /// Every area `area(of:)` names.
    static let areas = ["Web Apps", "Player", "Detection", "Updates", "Settings", "App"]

    static func area(of category: String) -> String {
        if category.contains("WebApp") || category.contains("Learning") { return "Web Apps" }
        if category.contains("Player") || category.contains("Playback") || category.contains("Fader") { return "Player" }
        if category.contains("Monitor") || category.contains("Meter") { return "Detection" }
        if category.contains("Update") { return "Updates" }
        if category == AutoHushLogger.settings.category || category.contains("LaunchAtLogin") { return "Settings" }
        return "App"
    }
}

private extension LogEntry {
    /// The same line as `other`, as read back from the file, which keeps
    /// times to the millisecond.
    func isSameLine(as other: LogEntry) -> Bool {
        abs(date.timeIntervalSince(other.date)) < 0.001 && level == other.level
            && category == other.category && message == other.message
    }
}
