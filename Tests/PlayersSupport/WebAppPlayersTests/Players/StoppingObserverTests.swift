import Testing
import AutoHushKit
import AutoHushTestSupport
import WebAppPlayers

@MainActor
@Suite("StoppingObserver")
struct StoppingObserverTests {
    @Test("stopping lifts the page's mute, unless it hands the pause over to a new monitoring of the same player; the observer it wraps stops either way")
    func liftsUnlessHandingOver() {
        let inner = MockStateObserver()
        let lifts = Locked(0)
        let observer = StoppingObserver(inner) { lifts.increment() }
        observer.start()
        #expect(inner.isObserving)
        observer.stop(handingOver: true)
        #expect(!inner.isObserving && lifts.value == 0)
        observer.start()
        observer.stop()
        #expect(!inner.isObserving && lifts.value == 1)
        observer.stop(handingOver: false)
        #expect(lifts.value == 2)
    }
}
