import Foundation
import Testing
@testable import AutoHushKit

@Suite("TaskSleepDebounceScheduler")
struct PlaybackArbiterDebounceSchedulingTests {
    @Test("the real debounce ends once its delay is over, not at once")
    func waitsItsDelay() async {
        let start = ContinuousClock.now
        await TaskSleepDebounceScheduler().scheduleDebounce(after: 0.2).value
        #expect(ContinuousClock.now - start >= .milliseconds(200))
    }
}
