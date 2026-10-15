import Foundation
import OSLog

/// What apps report to Now Playing, as MediaRemote's daemon writes it in
/// macOS's log (Player Check's sign, 2026-10-12): a sure state for an app
/// that can't be scripted, wherever its window is. Only an administrator can
/// read that log, and its wording is macOS's, not an API (checked on macOS
/// 27): so it's only ever an extra sign (the user, 2026-10-15), `nil` when
/// it can't be read. Read from where the last read ended, so each read is
/// short.
package final class NowPlayingReports: @unchecked Sendable {
    /// One app mediaremoted keeps for Now Playing: "com.spotify.client (380)
    /// Spotify", or a web app's media process "com.apple.WebKit.GPU/<its ID>".
    package struct Client: Equatable, Sendable {
        package var id: String
        package var state: PlayerState?
        package var removed = false
        /// When it last changed, in the order lines were read.
        package var order = 0
        /// The app's own bundle ID (a web app's, not WebKit's).
        package var appID: String { id.split(separator: "/").last.map(String.init) ?? id }
    }

    private let lock = NSLock()
    private var clients: [pid_t: Client] = [:]
    private var readUntil: Date?
    /// Whether the log could be opened when this was made.
    package let isAvailable: Bool
    /// How far back the first read goes.
    package static let firstLookBack: TimeInterval = 60 * 60
    /// How far each later read goes back over the one before.
    package static let overlap: TimeInterval = 10

    package init() {
        isAvailable = (try? OSLogStore.local()) != nil
    }

    /// The last state the app `bundleID` reported, read up to now; `nil`
    /// when it reported none, or the log can't be read. The log is opened
    /// afresh each time (about half a second): an open one doesn't see later
    /// lines (measured, 2026-10-15).
    package func state(of bundleID: String, now: Date = Date()) -> PlayerState? {
        guard isAvailable, let store = try? OSLogStore.local() else { return nil }
        return lock.withLock {
            // Lines reach the log a moment late: each read goes back over the last few seconds
            // again (read in order, so the last line read is still the newest).
            let start = readUntil.map { $0.addingTimeInterval(-Self.overlap) } ?? now.addingTimeInterval(-Self.firstLookBack)
            let predicate = NSPredicate(format: "process == %@ AND (composedMessage CONTAINS %@ OR composedMessage CONTAINS %@)",
                                        "mediaremoted", "nowPlayingClient", "PlaybackState changed")
            if let entries = try? store.getEntries(at: store.position(date: start), matching: predicate) {
                for case let entry as OSLogEntryLog in entries { Self.apply(entry.composedMessage, to: &clients) }
                readUntil = now
            }
            // The app's newest client (a web app's media process may come and go).
            return clients.values.filter { !$0.removed && $0.appID == bundleID && $0.state != nil }.max { $0.order < $1.order }?.state
        }
    }

    // The client: "<bundle ID>[/<bundle ID>] (<pid>) <name>", ending at ❯, 】, 〗 or "for".
    private static let clientPattern = try! NSRegularExpression(pattern: #"([A-Za-z0-9.\-]+(?:/[A-Za-z0-9.\-]+)?) \((\d+)\) (.*?)\s*(?:❯|】|〗| for |$)"#)
    private static let statePattern = try! NSRegularExpression(pattern: #"PlaybackState changed from (\w+) to (\w+)"#)

    /// One of the daemon's lines, applied to the client it names.
    package static func apply(_ message: String, to clients: inout [pid_t: Client]) {
        func group(_ match: NSTextCheckingResult, _ index: Int) -> String {
            Range(match.range(at: index), in: message).map { String(message[$0]) } ?? ""
        }
        let whole = NSRange(message.startIndex..., in: message)
        guard let match = clientPattern.firstMatch(in: message, range: whole), let pid = pid_t(group(match, 2)) else { return }
        let id = group(match, 1)
        var client = clients[pid] ?? Client(id: id)
        if id.count > client.id.count { client.id = id }
        if message.contains("Removing nowPlayingClient") {
            client.removed = true
        } else if message.contains("Creating nowPlayingClient") {
            client.removed = false
        } else if let state = statePattern.firstMatch(in: message, range: whole) {
            client.state = Self.state(reported: group(state, 2))
            client.order = (clients.values.map(\.order).max() ?? 0) + 1
        }
        clients[pid] = client
    }

    /// Playing, Paused and Stopped as they are; any other (Interrupted…) as paused.
    package static func state(reported: String) -> PlayerState {
        switch reported {
        case "Playing": .playing
        case "Stopped": .stopped
        default: .paused
        }
    }
}
