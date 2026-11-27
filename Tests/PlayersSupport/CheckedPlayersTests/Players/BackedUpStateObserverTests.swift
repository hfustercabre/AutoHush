import Testing
@testable import CheckedPlayers
import AutoHushKit
import AutoHushTestSupport
import WebAppPlayers

@MainActor
@Suite("BackedUpStateObserver")
struct BackedUpStateObserverTests {
    @Test("a stop that hands the pause over reaches its own player's observer as such: a web app's page keeps its mute for the new monitoring")
    func handOverReachesOwnObserver() {
        let lifts = Locked(0)
        let own = StoppingObserver(MockStateObserver()) { lifts.increment() }
        let observer = BackedUpStateObserver(own: own, backups: PolledStateObserver(read: { .unknown }, onChange: { _ in }),
                                             denied: { false })
        observer.start()
        observer.stop(handingOver: true)
        #expect(lifts.value == 0)
        observer.start()
        observer.stop()
        #expect(lifts.value == 1)
    }
}
