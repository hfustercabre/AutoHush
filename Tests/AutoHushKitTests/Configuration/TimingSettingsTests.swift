import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("TimingSettings")
struct TimingSettingsTests {
    @Test("defaults match the built-in configuration")
    func defaultsMatchConfiguration() {
        let configuration = AppConfiguration(timings: .defaults)
        let builtIn = AppConfiguration()
        #expect(configuration.sourceStartConfirmation == builtIn.sourceStartConfirmation)
        #expect(configuration.sourceStopGrace == builtIn.sourceStopGrace)
        #expect(configuration.debounceSeconds == builtIn.debounceSeconds)
        #expect(abs(configuration.audibleThreshold - builtIn.audibleThreshold) < 1e-7)
    }

    @Test("the silence threshold converts from dBFS to a linear level")
    func thresholdConversion() {
        #expect(abs(AppConfiguration(timings: TimingSettings(silenceThresholdDB: -40)).audibleThreshold - 0.01) < 1e-6)
    }

    @Test("values are clamped to their ranges")
    func clamping() {
        let clamped = TimingSettings(startConfirmation: -1, stopGrace: 50, resumeDelay: 9, silenceThresholdDB: 0).clamped
        #expect(clamped == TimingSettings(startConfirmation: 0, stopGrace: 10, resumeDelay: 5, silenceThresholdDB: -30))
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
