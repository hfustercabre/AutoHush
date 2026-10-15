import AppKit
import Observation
import AutoHushKit

/// Where the logs window reads AutoHush's log: `LogFile`; tests stand in.
protocol LogSource: AnyObject, Sendable {
    func entries(since date: Date) -> [LogEntry]
    func observe(_ handler: @escaping @Sendable (LogEntry) -> Void) -> UUID
    func stopObserving(_ token: UUID)
}

extension LogFile: LogSource {}

/// What the logs window shows: AutoHush's log since this launch, or over
/// the last 24 hours (earlier launches too), never further back; all of it
/// or only the problems, narrowed by a search, new lines added as they come.
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
        /// Errors and faults.
        case problems
    }

    var range = Range.thisLaunch {
        didSet { if range != oldValue { reload() } }
    }
    var levels = Levels.all
    var search = ""
    /// The list scrolls to each new line as it comes.
    var followsNewEntries = true
    private(set) var entries: [LogEntry] = []

    /// When this copy of AutoHush opened.
    @ObservationIgnored let launch: Date
    @ObservationIgnored private let source: (any LogSource)?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var observation: UUID?

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

    /// The lines shown: the problems only when asked, matching the search.
    var shown: [LogEntry] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return entries.filter { entry in
            (levels == .all || entry.level.isProblem)
                && (query.isEmpty || entry.message.localizedStandardContains(query)
                    || Self.area(of: entry.category).localizedStandardContains(query))
        }
    }

    /// The window opens: its lines, then each new one as it's logged.
    func open() {
        reload()
        guard observation == nil, let source else { return }
        observation = source.observe { [weak self] entry in
            Task { @MainActor in self?.append(entry) }
        }
    }

    /// The window closes: no more following.
    func close() {
        if let observation { source?.stopObserving(observation) }
        observation = nil
    }

    func reload() {
        entries = source?.entries(since: since) ?? []
    }

    /// A line just logged; those older than `since` go meanwhile.
    func append(_ entry: LogEntry) {
        let since = since
        guard entry.date >= since else { return }
        if let first = entries.first, first.date < since { entries.removeAll { $0.date < since } }
        entries.append(entry)
    }

    /// The lines shown, as text to copy or save: the date and time, the
    /// level, the area and the line.
    var text: String {
        shown.map { entry in
            "\(entry.date.formatted(Self.textDate))  \(entry.level.rawValue.capitalized)  \(Self.area(of: entry.category))  \(entry.message)"
        }.joined(separator: "\n")
    }

    private static let textDate = Date.VerbatimFormatStyle(
        format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)",
        timeZone: .current, calendar: Calendar(identifier: .gregorian))

    /// The part of AutoHush a logger's category belongs to, as the window
    /// shows it: in English, as the lines themselves are.
    static func area(of category: String) -> String {
        if category.contains("WebApp") || category.contains("Learning") { return "Web Apps" }
        if category.contains("Player") || category.contains("Playback") || category.contains("Fader") { return "Player" }
        if category.contains("Monitor") || category.contains("Meter") { return "Detection" }
        if category.contains("Update") { return "Updates" }
        return "App"
    }
}
