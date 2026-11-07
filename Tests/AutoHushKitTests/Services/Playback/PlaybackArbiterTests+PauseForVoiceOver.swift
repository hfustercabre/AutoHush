import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension PlaybackArbiterTests {
    // MARK: - Pause for VoiceOver turned off while VoiceOver plays

    private static let voiceOver = AppConfiguration.voiceOverBundleID

    /// The tests' configuration with Pause for VoiceOver off.
    private static var voiceOverOff: AppConfiguration {
        var configuration = AppConfiguration.testing
        configuration.pausesForVoiceOver = false
        return configuration
    }

    @Test("Pause for VoiceOver turned off while VoiceOver plays: the music it paused resumes at once, and VoiceOver's stop changes nothing")
    func voiceOverOffResumes() async {
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player)
        await arbiter.sourceChanged(Self.voiceOver, playing: true)
        #expect(await player.pauseCallCount == 1)

        await arbiter.setConfiguration(Self.voiceOverOff)
        await TestWait.until { await player.playCallCount == 1 }
        #expect(await arbiter.activeSources.isEmpty)

        await arbiter.sourceChanged(Self.voiceOver, playing: false) // the monitor's stop, after the grace
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 1)
        #expect(await player.pauseCallCount == 1)
    }

    @Test("Pause for VoiceOver turned off while VoiceOver and another app play: the music stays paused until the other app stops")
    func voiceOverOffWithAnotherApp() async {
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player)
        await arbiter.sourceChanged(Self.voiceOver, playing: true)
        await arbiter.sourceChanged("org.example.viewer", playing: true)

        await arbiter.setConfiguration(Self.voiceOverOff)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
        #expect(await arbiter.activeSources == ["org.example.viewer"])

        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
        #expect(await arbiter.activeSources.isEmpty)
    }
}
