import Foundation

/// Opens an app once AutoHush has quit: an update's new copy
/// (`UpdateInstaller`), or AutoHush again (Reopen AutoHush).
enum RelaunchWaiter {
    /// Opens `app` from a small shell loop that waits for AutoHush to exit;
    /// the loop outlives AutoHush. Calling the returned closure ends the loop
    /// instead.
    static func openAfterExit(_ app: URL) throws -> @Sendable () -> Void {
        try openAfterExit(app, waitingFor: getpid(), opener: URL(filePath: "/usr/bin/open"))
    }

    /// The same loop waiting for `pid` to exit, looking every `interval`
    /// seconds, then running `opener` with `app`: tests give a process, a
    /// script of their own and a shorter look, so their waits for nothing
    /// to happen are short too (B12, the full check, 2026-10-27).
    static func openAfterExit(_ app: URL, waitingFor pid: pid_t, opener: URL,
                              lookingEvery interval: Double = 0.2) throws -> @Sendable () -> Void {
        let waiter = Process()
        waiter.executableURL = URL(filePath: "/bin/sh")
        waiter.arguments = [
            "-c", #"while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep "$4"; done; exec "$3" "$2""#,
            "autohush-relaunch", String(pid), app.path, opener.path, String(interval),
        ]
        try waiter.run()
        let waiting = waiter.processIdentifier
        return { kill(waiting, SIGTERM) }
    }
}
