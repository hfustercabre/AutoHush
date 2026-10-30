import Foundation
import OSLog

// NowPlayingReports: the daemon's lines, read from the log and applied.
extension NowPlayingReports {
    private static let streamPredicate =
        #"process == "mediaremoted" AND (composedMessage CONTAINS "nowPlayingClient" OR composedMessage CONTAINS "PlaybackState changed")"#
    static let streamCommand = ["/usr/bin/log", "stream", "--style", "ndjson", "--predicate", streamPredicate]

    /// What the daemon wrote since `start`, from a store opened now; `nil`
    /// when the log can't be opened.
    static func readPast(since start: Date) -> [pid_t: Client]? {
        guard let store = try? OSLogStore.local() else { return nil }
        var past: [pid_t: Client] = [:]
        read(store, from: start, into: &past)
        return past
    }

    /// Reads what MediaRemote's daemon wrote in `store` from `start` into
    /// `clients`, by process: each client it creates and removes, and each
    /// one's "PlaybackState changed from … to …". False when the log can't
    /// be read from there. WebKit's media process is created under its own
    /// ID, then plays as "com.apple.WebKit.GPU/<the web app's ID>".
    @discardableResult
    package static func read(_ store: OSLogStore, from start: Date, into clients: inout [pid_t: Client]) -> Bool {
        let predicate = NSPredicate(format: "process == %@ AND (composedMessage CONTAINS %@ OR composedMessage CONTAINS %@)",
                                    "mediaremoted", "nowPlayingClient", "PlaybackState changed")
        guard let entries = try? store.getEntries(at: store.position(date: start), matching: predicate) else { return false }
        for case let entry as OSLogEntryLog in entries { apply(entry.composedMessage, at: entry.date, to: &clients) }
        return true
    }

    // The client: "<bundle ID>[/<bundle ID>] (<pid>) <name>", ending at ❯, 】, 〗 or "for".
    private static let clientPattern = try! NSRegularExpression(pattern: #"([A-Za-z0-9.\-]+(?:/[A-Za-z0-9.\-]+)?) \((\d+)\) (.*?)\s*(?:❯|】|〗| for |$)"#)
    private static let statePattern = try! NSRegularExpression(pattern: #"PlaybackState changed from (\w+) to (\w+)"#)

    /// One of the daemon's lines, written at `date`, applied to the client it names.
    static func apply(_ message: String, at date: Date = Date(), to clients: inout [pid_t: Client]) {
        func group(_ match: NSTextCheckingResult, _ index: Int) -> String {
            Range(match.range(at: index), in: message).map { String(message[$0]) } ?? ""
        }
        let whole = NSRange(message.startIndex..., in: message)
        guard let match = clientPattern.firstMatch(in: message, range: whole), let pid = pid_t(group(match, 2)) else { return }
        let id = group(match, 1)
        var client = clients[pid] ?? Client(id: id, pid: pid)
        if id.count > client.id.count { client.id = id }
        let name = group(match, 3)
        if !name.isEmpty { client.name = name }
        if message.contains("Removing nowPlayingClient") {
            client.removed = true
        } else if message.contains("Creating nowPlayingClient") {
            client.removed = false
        } else if let state = statePattern.firstMatch(in: message, range: whole) {
            client.reported = group(state, 2)
            client.changed = date
            client.order = (clients.values.map(\.order).max() ?? 0) + 1
        }
        clients[pid] = client
    }

    /// Playing, Paused and Stopped as they are; Unknown says nothing (`nil`:
    /// a player's trailers, heard, may report it); any other (Interrupted…) as paused.
    package static func state(reported: String) -> PlayerState? {
        switch reported {
        case "Playing": .playing
        case "Stopped": .stopped
        case "Unknown": nil
        default: .paused
        }
    }
}
