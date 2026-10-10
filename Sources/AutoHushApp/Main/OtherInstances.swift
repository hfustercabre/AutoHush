import AppKit

/// Other running copies of AutoHush: another version, another install, a
/// development build. Two copies would both pause and resume the music, so
/// the one opened last asks those opened before it to quit (`quitAll`).
struct OtherInstances: Sendable {
    /// The process IDs of the copies opened before this one and still running.
    let list: @Sendable () -> [pid_t]
    /// Sends a signal to a process.
    let send: @Sendable (_ pid: pid_t, _ signal: Int32) -> Void
    /// Whether a copy is still running: not once its process ID belongs to
    /// another process, so nothing else is ever sent a signal.
    let isRunning: @Sendable (pid_t) -> Bool

    /// The running apps with `bundleIdentifier` opened before this process.
    static func live(
        bundleIdentifier: String,
        ownPID: pid_t = getpid(),
        ownLaunch: Date? = NSRunningApplication.current.launchDate
    ) -> OtherInstances {
        OtherInstances(
            list: {
                NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                    .filter { isOlder(launch: $0.launchDate, pid: $0.processIdentifier, than: ownLaunch, ownPID: ownPID) }
                    .map(\.processIdentifier)
            },
            send: { pid, signal in _ = kill(pid, signal) },
            isRunning: { pid in
                // A copy that quit can have its process ID taken by another
                // process within seconds: that one isn't AutoHush.
                guard kill(pid, 0) == 0 || errno == EPERM,
                      let app = NSRunningApplication(processIdentifier: pid) else { return false }
                return app.bundleIdentifier == bundleIdentifier && !app.isTerminated
            }
        )
    }

    /// Whether a copy opened at `launch` (process `pid`) came before this one,
    /// so it's the one to quit. Two copies opened together can't both quit
    /// each other: at the same moment, the lower process ID quits. When
    /// either start is unknown, the other copy quits, as it always did.
    static func isOlder(launch: Date?, pid: pid_t, than ownLaunch: Date?, ownPID: pid_t) -> Bool {
        guard pid != ownPID else { return false }
        guard let launch, let ownLaunch else { return true }
        return launch != ownLaunch ? launch < ownLaunch : pid < ownPID
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
