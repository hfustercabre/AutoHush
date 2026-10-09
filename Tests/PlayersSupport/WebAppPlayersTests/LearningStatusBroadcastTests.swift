import Foundation
import Testing
import AutoHushKit
@testable import WebAppPlayers

@Suite("LearningStatusBroadcast", .timeLimit(.minutes(1)))
struct LearningStatusBroadcastTests {
    @Test("a listener added while the status changes is left with the current status, never an older one")
    func newListenerEndsOnCurrentStatus() async {
        for _ in 0..<500 {
            let broadcast = LearningStatusBroadcast()
            let sending = Task.detached { broadcast.send(.learned) }
            let updates = broadcast.updates()
            await sending.value
            // Only the newest status waits in the stream: it must be the current one.
            var iterator = updates.makeAsyncIterator()
            let newest = await iterator.next()
            #expect(newest == broadcast.current)
            if newest != broadcast.current { return }
        }
    }

    @Test("each listener hears every change after the status it started with")
    func listenersHearChanges() async {
        let broadcast = LearningStatusBroadcast()
        var iterator = broadcast.updates().makeAsyncIterator()
        #expect(await iterator.next() == .learning(hasPlayed: false))
        broadcast.send(.learning(hasPlayed: true))
        #expect(await iterator.next() == .learning(hasPlayed: true))
        broadcast.send(.learning(hasPlayed: true)) // no change, nothing sent
        broadcast.send(.learned)
        #expect(await iterator.next() == .learned)
    }
}
