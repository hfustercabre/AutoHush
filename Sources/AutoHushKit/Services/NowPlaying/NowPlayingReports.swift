import Foundation
import OSLog

/// What apps report to Now Playing, as MediaRemote's daemon writes it in
/// macOS's log (Player Check's sign, 2026-10-12): a sure state for an app
/// that can't be scripted, wherever its window is. Only an administrator can
/// read that log, and its wording is macOS's, not an API (checked on macOS
/// 27): so it's only ever an extra sign (the user, 2026-10-15), `nil` when
/// it can't be read. Player Check reads it the same way.
///
/// An open log store doesn't see later lines, and each opening takes about
/// half a second (measured, 2026-10-15): so the log is followed with one
/// `log stream`, started first, and the past read once from a store opened
/// then, so nothing falls between. It's followed from the first question
/// on, on a queue of its own, and stops once nobody asks for `idleLimit`.
package final class NowPlayingReports: @unchecked Sendable {
    /// One app mediaremoted keeps for Now Playing: "com.spotify.client (380)
    /// Spotify", or a web app's media process "com.apple.WebKit.GPU/<its ID>".
    package struct Client: Equatable, Sendable {
        package var id: String
        package var pid: pid_t
        /// As the log names it ("Creating nowPlayingClient" lines don't).
        package var name = ""
        /// Its last PlaybackState as the log says it (Playing, Paused,
        /// Stopped, Interrupted…); `nil` while it never reported one.
        package var reported: String?
        package var removed = false
        /// When it reported that state.
        package var changed: Date?
        /// When it last changed, in the order lines were read.
        var order = 0

        init(id: String, pid: pid_t = 0) {
            self.id = id
            self.pid = pid
        }

        /// The app's own bundle ID (a web app's, not WebKit's).
        package var appID: String { id.split(separator: "/").last.map(String.init) ?? id }
        /// What its report says.
        package var state: PlayerState? { reported.map(NowPlayingReports.state(reported:)) }
    }

    /// How far back the past is read when following starts.
    static let firstLookBack: TimeInterval = 60 * 60
    /// How long it's followed with nobody asking.
    static let idleLimit: TimeInterval = 60

    private let lock = NSLock()
    private var clients: [pid_t: Client] = [:]
    private var buffer = Data()
    /// The `log stream` followed, and whether the past was read since it started.
    private var stream: Process?
    private var streamID: ObjectIdentifier?
    private var ready = false
    private var starting = false
    /// The log couldn't be opened: it isn't asked again.
    private var failed = false
    private var lastAsked = Date.distantPast
    private var idleTimer: DispatchSourceTimer?
    private let lookBack: TimeInterval
    private let idle: TimeInterval?
    /// `log stream`'s command, then the past since a date as a store opened
    /// after it reads it (`nil`: the log can't be opened): tests stand in.
    private let streamCommand: [String]
    private let readPast: @Sendable (Date) -> [pid_t: Client]?
    /// Whether this account may read the log (`isAdministrator`).
    private let administrator: Bool
    private let queue = DispatchQueue(label: "AutoHush.NowPlayingReports", qos: .utility)

    /// Read already, whatever the account: what tests stand in for the log with.
    private var given = false

    /// `idleLimit` `nil`: followed until `stop` (Player Check's, for one run).
    /// `isAdministrator`: whether this account may read the log (tests that
    /// stand in for it, on any account, say yes).
    package init(lookBack: TimeInterval = NowPlayingReports.firstLookBack, idleLimit: TimeInterval? = NowPlayingReports.idleLimit,
                 streamCommand: [String] = NowPlayingReports.streamCommand,
                 isAdministrator: Bool = NowPlayingReports.isAdministrator,
                 readPast: @escaping @Sendable (Date) -> [pid_t: Client]? = NowPlayingReports.readPast(since:)) {
        self.lookBack = lookBack
        idle = idleLimit
        self.streamCommand = streamCommand
        administrator = isAdministrator
        self.readPast = readPast
    }

    /// Reports as `clients` say, not read from the log (tests) until `stop`:
    /// the next question then follows it, through `streamCommand` and `readPast`.
    convenience init(clients: [pid_t: Client], streamCommand: [String] = NowPlayingReports.streamCommand,
                     readPast: @escaping @Sendable (Date) -> [pid_t: Client]? = NowPlayingReports.readPast(since:)) {
        self.init(idleLimit: nil, streamCommand: streamCommand, readPast: readPast)
        self.clients = clients
        ready = true
        given = true
    }

    /// Whether the log can be read: an administrator's account (the admin
    /// group) can, until opening it showed otherwise. Told without opening it.
    package var isAvailable: Bool { lock.withLock { given || (administrator && !failed) } }

    /// Whether this account is an administrator's: macOS's log opens only to
    /// the admin group (80). Unknown, it's taken as one, and opening the log tells.
    package static let isAdministrator: Bool = {
        var groups = [gid_t](repeating: 0, count: 256)
        let count = getgroups(Int32(groups.count), &groups)
        return count < 0 || groups.prefix(Int(count)).contains(80)
    }()

    /// The app's newest client with a report (a web app's media process may
    /// come and go), whose process still runs: a crashed app's last report
    /// doesn't outlive it. `nil` when it reported none, while the log is
    /// first read (it's followed from then on), or when the log can't be read.
    package func latest(of bundleID: String, now: Date = Date()) -> Client? {
        guard isAvailable else { return nil }
        let ready = lock.withLock { () -> Bool in
            lastAsked = now
            return self.ready
        }
        guard ready else {
            followSoon()
            return nil
        }
        return lock.withLock { Self.latest(of: bundleID, in: clients) }
    }

    /// The newest of `clients` that is `bundleID`'s, reported a state, isn't
    /// removed and still runs.
    static func latest(of bundleID: String, in clients: [pid_t: Client],
                       stillRuns: (pid_t) -> Bool = NowPlayingReports.stillRuns) -> Client? {
        clients.values.filter { !$0.removed && $0.appID == bundleID && $0.reported != nil && stillRuns($0.pid) }
            .max { ($0.changed ?? .distantPast, $0.order) < ($1.changed ?? .distantPast, $1.order) }
    }

    /// Whether a process still runs (or runs as another user).
    package static func stillRuns(_ pid: pid_t) -> Bool { pid > 0 && (kill(pid, 0) == 0 || errno == EPERM) }

    /// Follows the log now, its past read back to `since`, before it
    /// returns (Player Check's run waits for it); whether it can be read.
    @discardableResult
    package func follow(since: Date) -> Bool {
        guard isAvailable else { return false }
        let start = lock.withLock { () -> Bool in
            guard !starting, !ready else { return false }
            starting = true
            return true
        }
        if start { startFollowing(since: since) }
        return lock.withLock { ready }
    }

    /// What the stream has read so far, ready or not: tests wait with it
    /// for a live line before the past is read.
    var clientsRead: [pid_t: Client] { lock.withLock { clients } }

    /// Ends the `log stream`, if it runs, and forgets what it read.
    package func stop() {
        let (process, timer) = lock.withLock { () -> (Process?, DispatchSourceTimer?) in
            defer {
                stream = nil
                streamID = nil
                ready = false
                clients = [:]
                buffer = Data()
                idleTimer = nil
            }
            return (stream, idleTimer)
        }
        timer?.cancel()
        // Only while it's still that stream: once it ended, its pid may be another process's.
        if let process, process.isRunning { process.terminate() }
    }

    private func followSoon() {
        let since = Date().addingTimeInterval(-lookBack)
        let start = lock.withLock { () -> Bool in
            guard !starting, !ready, !failed else { return false }
            starting = true
            return true
        }
        guard start else { return }
        queue.async { self.startFollowing(since: since) }
    }

    private func startFollowing(since: Date) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: streamCommand[0])
        process.arguments = Array(streamCommand.dropFirst())
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let id = ObjectIdentifier(process)
        // At its end (it ended, or was stopped) the handler would be called
        // again and again with nothing: it's removed.
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                self?.ended(id)
                return
            }
            self?.take(data, from: id)
        }
        lock.withLock {
            clients = [:]
            buffer = Data()
            stream = process
            streamID = id
        }
        guard (try? process.run()) != nil, let past = readPast(since) else {
            pipe.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
            lock.withLock {
                failed = true
                starting = false
                if streamID == id {
                    stream = nil
                    streamID = nil
                }
            }
            return
        }
        let kept = lock.withLock { () -> Bool in
            starting = false
            guard streamID == id else { return false }
            // What came live meanwhile is newer, but only for what it says: a
            // live line with no state (a client created again) keeps the past's.
            clients.merge(past) { live, old in
                var client = live
                if client.reported == nil { client.reported = old.reported; client.changed = old.changed }
                if client.name.isEmpty { client.name = old.name }
                if old.id.count > client.id.count { client.id = old.id }
                return client
            }
            ready = true
            return true
        }
        // Stopped meanwhile: this stream isn't followed.
        guard kept else {
            if process.isRunning { process.terminate() }
            return
        }
        watchIdle()
    }

    /// Stops following once nobody asked for `idle`.
    private func watchIdle() {
        guard let idle else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + idle / 2, repeating: idle / 2)
        timer.setEventHandler { [weak self] in
            guard let self, lock.withLock({ Date().timeIntervalSince(lastAsked) > idle }) else { return }
            stop()
        }
        let old = lock.withLock { () -> DispatchSourceTimer? in
            defer { idleTimer = timer }
            return idleTimer
        }
        old?.cancel()
        timer.resume()
    }

    /// The stream ended by itself: what's known may be old, so nothing is
    /// said until it's followed again (at the next question).
    private func ended(_ id: ObjectIdentifier) {
        lock.withLock {
            guard streamID == id else { return }
            stream = nil
            streamID = nil
            ready = false
            clients = [:]
        }
    }

    /// Lines from `log stream`, one JSON object each.
    private func take(_ data: Data, from id: ObjectIdentifier) {
        lock.withLock {
            guard streamID == id else { return }
            buffer.append(data)
            while let end = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<end]
                buffer.removeSubrange(buffer.startIndex...end)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let message = object["eventMessage"] as? String else { continue }
                Self.apply(message, at: Date(), to: &clients)
            }
        }
    }

    // MARK: - The daemon's lines

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

    /// Playing, Paused and Stopped as they are; any other (Interrupted…) as paused.
    package static func state(reported: String) -> PlayerState {
        switch reported {
        case "Playing": .playing
        case "Stopped": .stopped
        default: .paused
        }
    }
}
