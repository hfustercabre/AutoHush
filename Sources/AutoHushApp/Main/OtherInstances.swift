import AppKit

/// Other running copies of AutoHush: another version, another install, a
/// development build. Two copies would both pause and resume the music, so
/// the one opened last asks the others to quit (`quitAll`).
struct OtherInstances: Sendable {
    /// The process IDs of the other copies running now.
    let list: @Sendable () -> [pid_t]
    /// Sends a signal to a process.
    let send: @Sendable (_ pid: pid_t, _ signal: Int32) -> Void
    /// Whether a process is still running.
    let isRunning: @Sendable (pid_t) -> Bool

    /// The running apps with `bundleIdentifier`, but not this process.
    static func live(bundleIdentifier: String, ownPID: pid_t = getpid()) -> OtherInstances {
        OtherInstances(
            list: {
                NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                    .map(\.processIdentifier)
                    .filter { $0 != ownPID }
            },
            send: { pid, signal in _ = kill(pid, signal) },
            isRunning: { pid in kill(pid, 0) == 0 || errno == EPERM }
        )
    }

    /// Asks every other copy to quit (SIGTERM, which AutoHush answers by
    /// quitting normally: it restores the volume and hands over a pause),
    /// waits up to `grace` for them, then forces those still running
    /// (SIGKILL). Returns the copies there were.
    @discardableResult
    func quitAll(grace: Duration = .seconds(3), poll: Duration = .milliseconds(100)) async -> [pid_t] {
        let pids = list()
        guard !pids.isEmpty else { return [] }
        for pid in pids { send(pid, SIGTERM) }
        await waitForExit(of: pids, upTo: grace, poll: poll)
        let stuck = pids.filter(isRunning)
        for pid in stuck { send(pid, SIGKILL) }
        if !stuck.isEmpty { await waitForExit(of: stuck, upTo: .seconds(1), poll: poll) }
        return pids
    }

    private func waitForExit(of pids: [pid_t], upTo limit: Duration, poll: Duration) async {
        let clock = ContinuousClock()
        let deadline = clock.now + limit
        while pids.contains(where: isRunning), clock.now < deadline {
            try? await Task.sleep(for: poll)
        }
    }
}
