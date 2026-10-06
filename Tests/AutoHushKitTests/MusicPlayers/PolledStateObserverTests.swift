import Foundation
import Testing
@testable import AutoHushKit

/// A player state the test changes, counting how often it was read.
private final class FakeState: @unchecked Sendable {
    private let lock = NSLock()
    private var _state: PlayerState
    private var _reads = 0

    init(_ state: PlayerState) { _state = state }

    var state: PlayerState {
        get { lock.withLock { _state } }
        set { lock.withLock { _state = newValue } }
    }
    var reads: Int { lock.withLock { _reads } }

    func read() -> PlayerState {
        lock.withLock {
            _reads += 1
            return _state
        }
    }
}

@MainActor
@Suite("PolledStateObserver")
struct PolledStateObserverTests {
    @Test("reports each change once, says nothing for unknown states, and nothing after stop")
    func changes() async throws {
        let player = FakeState(.playing)
        var states: [PlayerState] = []
        let observer = PolledStateObserver(interval: .milliseconds(20), read: { player.read() }) { states.append($0) }
        observer.start()
        for _ in 0..<100 where states.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        player.state = .unknown // a read that failed
        try await Task.sleep(for: .milliseconds(60))
        player.state = .paused
        for _ in 0..<100 where states.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        player.state = .notRunning // quit
        for _ in 0..<100 where states.count < 3 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(states == [.playing, .paused, .notRunning])

        observer.stop()
        player.state = .playing
        try await Task.sleep(for: .milliseconds(100))
        #expect(states == [.playing, .paused, .notRunning])
    }

    @Test("an observer let go of without stop() stops reading")
    func released() async throws {
        let player = FakeState(.paused)
        var observer: PolledStateObserver? = PolledStateObserver(interval: .milliseconds(10), read: { player.read() }) { _ in }
        observer?.start()
        for _ in 0..<100 where player.reads == 0 { try await Task.sleep(for: .milliseconds(5)) }
        observer = nil
        try await Task.sleep(for: .milliseconds(50)) // a read under way finishes
        let reads = player.reads
        try await Task.sleep(for: .milliseconds(100))
        #expect(player.reads == reads)
    }
}
