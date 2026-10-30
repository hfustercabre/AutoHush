import Foundation
import Testing
@testable import AutoHushApp
@testable import AutoHushKit
import AutoHushTestSupport

extension PlayerSessionTests {
    // MARK: - Settings and sleep

    @MainActor
    @Test("settings reach the chosen player's monitoring and the held pauses, which follow all but the timings")
    func settingsReachMonitorings() async {
        let bench = Bench()
        let session = await bench.holdingFirst()
        let held = bench.monitorings.of(Players.first)[0]
        let current = bench.monitorings.of(Players.second)[0]

        session.settings.autoPause = false
        #expect(current.autoPause == false && held.autoPause == false)
        session.settings.ignored = [Self.viewer.id]
        #expect(current.ignored == [Self.viewer.id] && held.ignored == [Self.viewer.id])
        session.settings.timings = TimingSettings(stopGrace: 4)
        #expect(current.configurations.map(\.musicPlayerBundleID) == [Players.second])
        #expect(current.configurations.first?.sourceStopGrace == 4)
        session.settings.detection = .playbackSignals
        #expect(current.detectionMethods == [.playbackSignals])
        // AntiDot mode leaves no audio taps behind in a held pause.
        #expect(held.detectionMethods == [.playbackSignals])
        #expect(held.configurations.isEmpty)

        let unchanged = session.settings
        session.settings = unchanged // nothing changed: nothing sent
        #expect(current.configurations.count == 1 && current.detectionMethods.count == 1)
    }

    @MainActor
    @Test("the Mac asleep: the monitoring knows, held pauses end, and one started meanwhile knows too")
    func sleep() async {
        let bench = Bench()
        let session = await bench.holdingFirst()
        let held = bench.monitorings.of(Players.first)[0]
        let current = bench.monitorings.of(Players.second)[0]

        session.setAsleep(true)
        session.setAsleep(true)
        #expect(current.asleep == [true])
        #expect(held.isStopped)

        session.retry() // the player relaunched in a dark wake, say
        await TestWait.until { bench.monitorings.of(Players.second).count == 2 }
        await TestWait.until { session.state.health == .ready }
        #expect(bench.monitorings.of(Players.second)[1].starts.map(\.asleep) == [true])
        session.setAsleep(false)
        #expect(bench.monitorings.of(Players.second)[1].asleep == [false])
    }

    @MainActor
    @Test("resumes held: the monitoring and the held pauses know, one started meanwhile starts held, and all hear the release")
    func holdResumes() async {
        let bench = Bench()
        let session = await bench.holdingFirst()
        let held = bench.monitorings.of(Players.first)[0]
        let current = bench.monitorings.of(Players.second)[0]
        #expect(current.setup?.resumesHeld == false)

        session.holdResumes(true)
        session.holdResumes(true)
        #expect(current.resumesHeld == [true] && held.resumesHeld == [true])

        session.retry() // the player reopened during Add an App's check, say
        await TestWait.until { bench.monitorings.of(Players.second).count == 2 }
        await TestWait.until { session.state.health == .ready }
        let restarted = bench.monitorings.of(Players.second)[1]
        #expect(restarted.setup?.resumesHeld == true)
        session.holdResumes(false)
        #expect(restarted.resumesHeld == [false] && held.resumesHeld == [true, false])
    }
}
