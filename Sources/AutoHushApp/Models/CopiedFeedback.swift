import Foundation
import Observation

/// "Copied" for a moment after a Copy button's click (`CopyButton`): a click
/// meanwhile starts the moment over, so the word never goes early (the full
/// check, 2026-10-19: a second click within 2 s cut it short).
@MainActor
@Observable
final class CopiedFeedback {
    /// How long "Copied" shows.
    static let duration = Duration.seconds(2)

    private(set) var isShown = false
    @ObservationIgnored private var reset: Task<Void, Never>?
    @ObservationIgnored private let sleep: @Sendable (Duration) async -> Void

    init(sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    /// Shows "Copied" for `duration` from now.
    func show() {
        isShown = true
        reset?.cancel()
        reset = Task { [weak self, sleep] in
            await sleep(Self.duration)
            guard !Task.isCancelled else { return }
            self?.isShown = false
        }
    }
}
