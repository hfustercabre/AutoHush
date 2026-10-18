import CoreAudio
import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("SystemVolumeLeveler")
struct SystemVolumeLevelerTests {
    @Test("lowers each channel by as much, never below the lowest, and puts it back over the fade-out in steps")
    func lowersAndRestores() async {
        let volume = MockSystemVolume([1: -12, 2: -14], lowest: -20), suite = TestDefaults("SystemVolumeLevelerTests"), defaults = suite.defaults
        defer { suite.remove() }
        let leveler = SystemVolumeLeveler(volume: volume, defaults: defaults, sleep: { _ in })
        leveler.lower(by: -6)
        #expect(volume.decibels == [1: -18, 2: -20]) // the balance kept, -20 the lowest
        leveler.lower(by: -3) // already lowered: once only
        #expect(volume.decibels == [1: -18, 2: -20])

        leveler.restore(over: 0.2)
        await TestWait.until { defaults.data(forKey: SystemVolumeLeveler.leftKey) == nil } // back: nothing kept
        #expect(volume.decibels == [1: -12, 2: -14])
        #expect(volume.sets.count == 1 + 4) // lowered, then 4 steps of 50 ms
        #expect(volume.sets[1] == [1: -16.5, 2: -18.5])
    }

    @Test("the user's own change wins: a volume changed meanwhile is left as it is")
    func userChangeWins() {
        let volume = MockSystemVolume([0: -10]), suite = TestDefaults("SystemVolumeLevelerTests"), defaults = suite.defaults
        defer { suite.remove() }
        let leveler = SystemVolumeLeveler(volume: volume, defaults: defaults, sleep: { _ in })
        leveler.lower(by: -8)
        volume.decibels = [0: -25] // the volume keys
        leveler.restoreNow()
        #expect(volume.decibels == [0: -25])
        #expect(defaults.data(forKey: SystemVolumeLeveler.leftKey) == nil)
    }

    @Test("an output with no volume control is left alone, and so is a restore with nothing lowered")
    func noControl() {
        let volume = MockSystemVolume(nil)
        let suite = TestDefaults("SystemVolumeLevelerTests")
        defer { suite.remove() }
        let leveler = SystemVolumeLeveler(volume: volume, defaults: suite.defaults, sleep: { _ in })
        leveler.lower(by: -8)
        leveler.restoreNow()
        #expect(volume.sets.isEmpty)
    }

    @Test("what it lowered is kept until it's put back: after a quit or a crash, the next launch puts it back, unless the user changed it since")
    func putBackAtLaunch() {
        let volume = MockSystemVolume([0: -10]), suite = TestDefaults("SystemVolumeLevelerTests"), defaults = suite.defaults
        defer { suite.remove() }
        func launch() -> SystemVolumeLeveler { SystemVolumeLeveler(volume: volume, defaults: defaults, sleep: { _ in }) }
        launch().lower(by: -8) // AutoHush quits or crashes with the music lowered
        #expect(volume.decibels == [0: -18])
        launch().restoreIfLeft()
        #expect(volume.decibels == [0: -10])
        launch().restoreIfLeft() // nothing left: nothing changes
        #expect(volume.sets.count == 2)

        launch().lower(by: -8)
        volume.decibels = [0: -30] // the volume keys, before the next launch
        launch().restoreIfLeft()
        #expect(volume.decibels == [0: -30])
        #expect(defaults.data(forKey: SystemVolumeLeveler.leftKey) == nil) // forgotten
    }

    @Test("nothing waits for the glide back up: a put-back at once, or a resume lowering again, stops it where it is")
    func glideStops() {
        let volume = MockSystemVolume([0: -10]), suite = TestDefaults("SystemVolumeLevelerTests"), defaults = suite.defaults
        defer { suite.remove() }
        // Each step of the glide waits here, until the test lets it go on.
        let stepped = DispatchSemaphore(value: 0), goOn = DispatchSemaphore(value: 0)
        let leveler = SystemVolumeLeveler(volume: volume, defaults: defaults, sleep: { _ in
            stepped.signal()
            goOn.wait()
        })
        leveler.lower(by: -8)
        leveler.restore(over: 0.2) // 4 steps: -16, -14, -12, -10
        stepped.wait()
        #expect(volume.decibels == [0: -16])

        // The music resumes again: from the volume it was going back to.
        leveler.lower(by: -6)
        #expect(volume.decibels == [0: -16])
        goOn.signal() // the old glide wakes, stopped

        // The next one, after it on its queue: it set nothing more meanwhile.
        leveler.restore(over: 0.2)
        stepped.wait()
        #expect(volume.sets == [[0: -18], [0: -16], [0: -10], [0: -16], [0: -14.5]])

        // Settings or a stop: at once, while the glide waits.
        leveler.restoreNow()
        #expect(volume.decibels == [0: -10])
        #expect(defaults.data(forKey: SystemVolumeLeveler.leftKey) == nil)
        goOn.signal()
    }
}
