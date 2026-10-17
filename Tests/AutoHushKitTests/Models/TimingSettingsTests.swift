import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("TimingSettings")
struct TimingSettingsTests {
    @Test("the silence threshold converts from dBFS to a linear level; by default −60 dBFS, 0.001")
    func thresholdConversion() {
        #expect(abs(AppConfiguration(timings: TimingSettings(silenceThresholdDB: -40)).audibleThreshold - 0.01) < 1e-6)
        #expect(abs(AppConfiguration().audibleThreshold - 0.001) < 1e-7)
    }

    @Test("values are clamped to their ranges")
    func clamping() {
        let clamped = TimingSettings(startConfirmation: -1, stopGrace: 50, silenceThresholdDB: 0).clamped
        #expect(clamped == TimingSettings(startConfirmation: 0, stopGrace: 10, silenceThresholdDB: -30))
    }

    @Test("fades are on by default; off, both last 0 s, and the durations chosen are kept")
    func fadesSwitch() {
        #expect(TimingSettings.defaults.fadesEnabled)
        let off = TimingSettings(fadeOutDuration: 3, fadeInDuration: 4, fadesEnabled: false)
        #expect(off.clamped == off)
        let configuration = AppConfiguration(timings: off)
        #expect(configuration.fadeOutDuration == 0 && configuration.fadeInDuration == 0)
        let on = AppConfiguration(timings: TimingSettings(fadeOutDuration: 3, fadeInDuration: 4))
        #expect(on.fadeOutDuration == 3 && on.fadeInDuration == 4)
    }

    @Test("Level other apps and Stay paused after calls are off by default, and reach the configuration")
    func advancedSwitches() {
        #expect(!TimingSettings.defaults.levelsMusic && !TimingSettings.defaults.staysPausedAfterCalls)
        let on = TimingSettings(levelsMusic: true, staysPausedAfterCalls: true)
        #expect(on.clamped == on)
        let configuration = AppConfiguration(timings: on)
        #expect(configuration.levelsMusic && configuration.staysPausedAfterCalls)
    }

    @Test("an app counts as stopped after at least a second of silence")
    func stopGraceMinimum() {
        #expect(TimingSettings(stopGrace: 0).clamped.stopGrace == 1)
        #expect(TimingSettings(stopGrace: 0.5).clamped.stopGrace == 1)
        #expect(AppConfiguration(timings: TimingSettings(stopGrace: 0)).sourceStopGrace == 1)
    }

    @Test("the tracker adopts new timings without forgetting sources")
    func trackerUpdate() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        var tracker = SourceActivityTracker(startConfirmation: 5, gapTolerance: 0.5, stopGrace: 2)
        _ = tracker.update(audible: ["a"], at: t0)
        tracker.updateTimings(from: AppConfiguration(timings: TimingSettings(startConfirmation: 1)))
        let started = tracker.update(audible: ["a"], at: t0 + 1).started
        #expect(started == ["a"])
    }
}
