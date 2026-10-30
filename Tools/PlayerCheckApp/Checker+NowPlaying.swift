import Foundation
import PlayerCheckKit

/// macOS's own Now Playing list, as playercheck reads it.
extension Checker {
    /// Reads macOS's Now Playing list again: all of it (the log since the
    /// Mac started: seconds on a Mac up for days) at first and when asked,
    /// else only what changed since the last read.
    func readClients(full: Bool = false) {
        guard let tool else {
            clientsProblem = "playercheck is missing from this app: build it with build.sh."
            return
        }
        guard !isReadingClients else {
            readAgain = (readAgain ?? false) || full
            return
        }
        isReadingClients = true
        let since = full ? nil : clientsReadAt
        let started = Date()
        // A little overlap, so nothing written meanwhile is missed.
        let arguments = since.map { CommandLineOptions.nowPlayingList(since: $0.addingTimeInterval(-2)) } ?? CommandLineOptions.nowPlayingList(hours: nil)
        Task {
            let (status, output) = await Checker.runAndWait(tool, arguments)
            if status == CheckExitStatus.done {
                var updated = since == nil ? [:] : clients
                var active: pid_t?
                for line in output.split(separator: "\n") {
                    if let pid = NowPlayingListLine.active(in: line) {
                        active = pid
                    } else if let client = NowPlayingListLine(line: line) {
                        if client.state == NowPlayingListLine.removed {
                            if updated[client.bundleID]?.pid == client.pid { updated[client.bundleID] = nil }
                        } else if client.state == NowPlayingListLine.registered, updated[client.bundleID]?.pid == client.pid {
                            // An update names a client it saw without a state (logged
                            // again, created again): the state known for that process
                            // still holds, as playercheck's own check keeps it.
                        } else {
                            updated[client.bundleID] = client
                        }
                    }
                }
                if let active {
                    updated = updated.mapValues { client in
                        var client = client
                        client.isActive = client.pid == active
                        return client
                    }
                }
                clients = updated
                clientsReadAt = started
                clientsProblem = nil
            } else {
                clients = [:]
                // Nothing kept to update: the next read is a full one.
                clientsReadAt = nil
                clientsProblem = "macOS's own Now Playing list couldn't be read: "
                    + output.trimmingCharacters(in: .whitespacesAndNewlines) + " (it needs an administrator account)."
            }
            isReadingClients = false
            if let again = readAgain {
                readAgain = nil
                readClients(full: again)
            }
        }
    }

    /// Its entry in macOS's Now Playing list, while it runs (a list kept up
    /// to date by changes only may still hold an app that quit).
    func client(of app: InstalledApp) -> NowPlayingListLine? {
        guard isRunning(app) else { return nil }
        return app.bundleID.flatMap { clients[$0] }
    }

    /// The apps that can be in Now Playing: built for it, or listed there now.
    var nowPlayingApps: [InstalledApp] {
        apps.filter { $0.nowPlayingReason != nil || client(of: $0) != nil }
    }
}

/// What the list says of an app's line in Now Playing.
extension NowPlayingListLine {
    var summary: String { isActive ? "Now Playing (\(state))" : "In Now Playing: \(state)" }
}
