import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

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

/// Holds whoever waits on it until it's opened.
private actor Gate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}

@MainActor
@Suite("PolledStateObserver")
struct PolledStateObserverTests {
    @Test("reports each change once, says nothing for unknown states, and nothing after stop; changes are declared up to 1.5 s late")
    func changes() async throws {
        #expect(PolledStateObserver.reportDelay == 1.5) // the interval, and a menu read's 0.5 s
        let player = FakeState(.playing)
        var states: [PlayerState] = []
        let observer = PolledStateObserver(interval: .milliseconds(20), read: { player.read() }) { states.append($0) }
        observer.start()
        await TestWait.until { !states.isEmpty }
        player.state = .unknown // a read that failed
        let reads = player.reads
        await TestWait.until { player.reads >= reads + 2 } // read twice since: a read of it was delivered
        player.state = .paused
        await TestWait.until { states.count >= 2 }
        player.state = .notRunning // quit
        await TestWait.until { states.count >= 3 }
        #expect(states == [.playing, .paused, .notRunning])

        observer.stop()
        player.state = .playing
        try await Task.sleep(for: .milliseconds(100))
        #expect(states == [.playing, .paused, .notRunning])
    }

    @Test("an observer let go of without stop() stops reading")
    func released() async throws {
        let player = FakeState(.paused)
        let gate = Gate()
        var observer: PolledStateObserver? = PolledStateObserver(interval: .milliseconds(10), read: {
            let state = player.read()
            await gate.wait()
            return state
        }) { _ in }
        observer?.start()
        await TestWait.until { player.reads > 0 } // its first read, held
        observer = nil
        await gate.open()
        try await Task.sleep(for: .milliseconds(100))
        #expect(player.reads == 1)
    }
}
