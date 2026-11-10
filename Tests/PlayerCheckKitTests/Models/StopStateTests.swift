import Testing
@testable import PlayerCheckKit

@Suite("StopState")
struct StopStateTests {
    @Test("a stop ends the check at once, unless a trial runs or the app's window is away, when the check stops itself; once a stop came, nothing moves")
    func answers() {
        let idle = StopState()
        #expect(!idle.isRequested && idle.since == nil)
        #expect(!idle.request()) // at once
        #expect(idle.isRequested && idle.since != nil)
        #expect(!idle.beginMoving() && !idle.isWindowAway)

        let trial = StopState()
        trial.setInTrial(true)
        #expect(trial.request()) // after the trial, which plays the app again
        trial.setInTrial(false)
        #expect(!trial.request())

        let moving = StopState()
        #expect(moving.beginMoving() && moving.isWindowAway)
        #expect(moving.request()) // after the window is back
        let first = moving.since
        #expect(moving.request() && moving.since == first) // the first stop's time is kept
        moving.windowBack()
        #expect(!moving.isWindowAway && !moving.request())
    }

    @Test("a press test with no window trip holds a stop between its trials, so the app a trial left paused is played again first; once it ends, a stop ends the check at once")
    func holdsWithoutWindowTrip() {
        let test = StopState()
        test.setHolding(true)
        #expect(test.request()) // the check stops itself, once the app plays again
        #expect(!test.isWindowAway) // nothing to put back
        test.setHolding(false)
        #expect(!test.request())
    }
}
