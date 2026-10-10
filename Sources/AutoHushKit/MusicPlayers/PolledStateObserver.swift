import Foundation

/// Reports the state of a player that announces nothing, by reading it about
/// once a second while observing. Only changes are reported, and only states
/// that say something. The player quitting shows up as `.notRunning` at the
/// next read.
@MainActor
package final class PolledStateObserver: PlayerStateObserving {
    /// How often the state is read.
    package nonisolated static let interval: Duration = .seconds(1)
    /// How late a change can be reported: a read's interval, in seconds, as
    /// the players read this way declare it (`MusicPlayer.stateReportDelay`).
    package nonisolated static var reportDelay: TimeInterval {
        let (seconds, attoseconds) = interval.components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }

    private let read: @Sendable () async -> PlayerState
    private let interval: Duration
    private let onChange: @MainActor (PlayerState) -> Void
    private var polling: Task<Void, Never>?
    private var lastState: PlayerState?

    package init(
        interval: Duration = PolledStateObserver.interval,
        read: @escaping @Sendable () async -> PlayerState,
        onChange: @escaping @MainActor (PlayerState) -> Void
    ) {
        self.read = read
        self.interval = interval
        self.onChange = onChange
    }

    package func start() {
        guard polling == nil else { return }
        let read = read
        let interval = interval
        polling = Task { [weak self] in
            while !Task.isCancelled {
                let state = await read()
                // Gone without stop(): nothing more to read for.
                guard !Task.isCancelled, self != nil else { return }
                self?.deliver(state)
                try? await Task.sleep(for: interval)
            }
        }
    }

    package func stop() {
        polling?.cancel()
        polling = nil
        lastState = nil
    }

    private func deliver(_ state: PlayerState) {
        guard polling != nil, state != .unknown, state != lastState else { return }
        lastState = state
        onChange(state)
    }
}
