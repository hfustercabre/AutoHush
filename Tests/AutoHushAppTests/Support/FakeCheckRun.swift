import Foundation
import Testing
@testable import AutoHushApp
import AutoHushTestSupport
import CheckedPlayers

/// A check that ends when the test says.
@MainActor
final class FakeCheckRun: CheckRunning {
    var stopped = false
    /// Stopped, it ends at once; else it puts things back first, until `finish`.
    var endsWhenStopped = true
    private var end: PlayerCheckEnd?
    private var waiting: [CheckedContinuation<PlayerCheckEnd, Never>] = []

    func stop() {
        stopped = true
        if endsWhenStopped { finish(.stopped) }
    }

    func finish(_ end: PlayerCheckEnd) {
        self.end = end
        waiting.forEach { $0.resume(returning: end) }
        waiting = []
    }

    func waitForEnd() async -> PlayerCheckEnd {
        if let end { return end }
        return await withCheckedContinuation { waiting.append($0) }
    }
}
