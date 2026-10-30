import Foundation
import os
import AutoHushKit
import ScriptablePlayers

/// An app scripted with Apple events, without the app: its process, its
/// consent asked, and what it was sent. Each fake answers its own events
/// (`send`), reading them with `SentEvent`; its suites take
/// `.appleEventCoercions`.
package protocol FakeAppleEventApp: AppleEventSending {
    associatedtype State: AppleEventAppState
    var state: OSAllocatedUnfairLock<State> { get }
}

extension FakeAppleEventApp {
    package var sent: [String] { state.withLock { $0.sent } }

    package func processIdentifier() -> pid_t? { state.withLock { $0.pid } }

    package func runningProcessIdentifier() throws -> pid_t {
        guard let pid = processIdentifier() else { throw MusicPlayerError.playerNotRunning }
        return pid
    }

    package func requestPermission(pid: pid_t) async throws { state.withLock { $0.sent.append("ask") } }
}
