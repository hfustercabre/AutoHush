import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@MainActor
@Suite("PolledStateObserver", .waitsTimeLimit)
struct PolledStateObserverTests {
    @Test("reports each change once, says nothing for unknown states, and nothing after stop; changes are declared up to 1.5 s late")
    func changes() async throws {
        #expect(PolledStateObserver.reportDelay == 1.5) // the interval, and a menu read's 0.5 s
        let player = FakePlayerState(.playing)
        let sleep = ManualSleep()
        var states: [PlayerState] = []
        let observer = PolledStateObserver(read: { player.read() }, sleep: sleep.sleep) { states.append($0) }
        observer.start()
        // Each round: a read, then a sleep the test ends with step().
        await TestWait.until { sleep.sleeping == 1 }
        #expect(states == [.playing])
        player.state = .unknown // a read that failed
        sleep.step()
        await TestWait.until { player.reads == 2 && sleep.sleeping == 1 }
        #expect(states == [.playing])
        player.state = .paused
        sleep.step()
        await TestWait.until { states.count >= 2 }
        player.state = .notRunning // quit
        sleep.step()
        await TestWait.until { states.count >= 3 }
        #expect(states == [.playing, .paused, .notRunning])
        #expect(sleep.durations.allSatisfy { $0 == PolledStateObserver.interval })

        await TestWait.until { sleep.sleeping == 1 }
        let polling = try #require(observer.polling)
        let reads = player.reads
        observer.stop()
        player.state = .playing
        await ends(polling) // the loop ended on its cancelled sleep
        #expect(player.reads == reads)
        #expect(states == [.playing, .paused, .notRunning])
    }

    @Test("an observer let go of without stop() stops reading")
    func released() async throws {
        let player = FakePlayerState(.paused)
        let gate = Gate()
        let sleep = ManualSleep()
        var observer: PolledStateObserver? = PolledStateObserver(read: {
            let state = player.read()
            await gate.wait()
            return state
        }, sleep: sleep.sleep) { _ in }
        observer?.start()
        await TestWait.until { player.reads > 0 } // its first read, held
        let polling = try #require(observer?.polling)
        observer = nil
        await gate.open()
        await ends(polling) // it ended without sleeping or reading again
        #expect(player.reads == 1)
        #expect(sleep.durations.isEmpty)
    }

    /// Waits for the reading loop to end: a loop that goes on fails the
    /// test at the wait's limit instead of hanging the run (`Task.value`
    /// ignores the test's time limit).
    private func ends(_ polling: Task<Void, Never>) async {
        let ended = Locked(false)
        Task { await polling.value; ended.withLock { $0 = true } }
        await TestWait.until { ended.value }
    }
}
