import Testing
@testable import AutoHushApp
import AutoHushKit

/// Fine-Tuning's Detection card in words (T10b, the user's pick,
/// 2026-11-02): AntiDot mode's ways by what counts, one short sentence each.
@Suite("Detection's texts")
struct DetectionTextTests {
    @Test("AntiDot mode's ways: what apps tell macOS, or any app with sound on")
    func titles() {
        #expect(DetectionMethod.antiDotWays.map(\.title) == ["What apps tell macOS", "Any app with sound on"])
        #expect(DetectionMethod.audioLevels.title == "Measure audio levels")
    }

    @Test("each way says what counts in one sentence")
    func summaries() {
        #expect(DetectionMethod.audioLevels.summary == "Most accurate; macOS shows its purple dot.")
        #expect(DetectionMethod.playbackSignals.summary == "Apps count while they tell macOS they play.")
        #expect(DetectionMethod.openStreams.summary == "Paused apps count too; short sounds don’t.")
    }

    @Test("the silence threshold, dimmed in AntiDot mode, says so as Volume Limits does")
    func thresholdNote() {
        #expect(AntiDotText.featureOff == "Off in AntiDot mode")
    }
}
