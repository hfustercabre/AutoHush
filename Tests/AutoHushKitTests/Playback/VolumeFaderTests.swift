import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

/// Counts fade steps and can run something at a given step, so tests can
/// interrupt a fade halfway without waiting for real time.
private actor StepGate {
    private(set) var steps = 0
    private var actions: [Int: @Sendable () async -> Void] = [:]

    func at(step: Int, _ action: @escaping @Sendable () async -> Void) { actions[step] = action }

    func tick() async {
        steps += 1
        if let action = actions.removeValue(forKey: steps) { await action() }
    }
}

@Suite("VolumeFader")
struct VolumeFaderTests {
    private func makeFader(
        _ player: MockMusicPlayer, fadeOut: TimeInterval = 2, fadeIn: TimeInterval = 3, gate: StepGate = StepGate()
    ) -> VolumeFader {
        VolumeFader(player: player, fadeOut: fadeOut, fadeIn: fadeIn, sleep: { _ in await gate.tick() })
    }

    @Test("fades out 50 dB below the user's volume, pauses, then sets that volume back")
    func fadesOut() async throws {
        let player = MockMusicPlayer(state: .playing, volumeCurve: .cubic)
        await player.setVolumeLevel(60)

        #expect(try await makeFader(player).fadeOutAndPause())

        let ramp = await Array(player.volumeHistory.dropLast())
        #expect(ramp == ramp.sorted(by: >)) // only ever down
        // 60 is −13.3 dB on a cube law; 50 dB lower is volume 8.8.
        #expect(ramp.last == 9)
        #expect(await player.commandLog.suffix(2) == ["pause", "volume 60"])
        #expect(await player.volumeLevel == 60)
    }

    @Test("a fade moves in even steps of loudness, not of the volume number")
    func logarithmicSteps() async throws {
        let player = MockMusicPlayer(state: .playing, volumeCurve: .cubic)
        await player.setVolumeLevel(100)

        #expect(try await makeFader(player, fadeOut: 2).fadeOutAndPause())

        // 20 steps over 50 dB: about 2.5 dB each, give or take rounding.
        let levels = await player.volumeHistory.dropLast().map { VolumeCurve.cubic.decibels(atVolume: Double($0)) }
        let steps = zip(levels, levels.dropFirst()).map { $0 - $1 }
        #expect(levels.count == 20)
        #expect(steps.allSatisfy { (1.5...3.6).contains($0) })
        // A linear ramp on the volume number would instead take 0.4 dB steps at
        // the top and over 10 dB at the bottom.
    }

    @Test("plays from near silence, then fades in to the user's volume")
    func fadesIn() async throws {
        let player = MockMusicPlayer(state: .paused, volumeCurve: .cubic)
        await player.setVolumeLevel(60)

        try await makeFader(player).playAndFadeIn()

        #expect(await player.commandLog.prefix(2) == ["volume 9", "play"]) // 50 dB below 60
        let history = await player.volumeHistory
        #expect(history == history.sorted()) // only ever up
        #expect(await player.volumeLevel == 60)
    }

    @Test("a player without a volume pauses and plays without fading")
    func noVolume() async throws {
        let player = MockMusicPlayer(state: .playing)
        let fader = makeFader(player)
        #expect(try await fader.fadeOutAndPause())
        try await fader.playAndFadeIn()
        #expect(await player.commandLog == ["pause", "play"])
    }

    @Test("fading out and fading in each take their own time")
    func separateDurations() async throws {
        let player = MockMusicPlayer(state: .playing)
        await player.setVolumeLevel(60)
        let gate = StepGate()
        let fader = makeFader(player, fadeOut: 2, fadeIn: 3, gate: gate)

        #expect(try await fader.fadeOutAndPause())
        let fadeOutSteps = await gate.steps
        try await fader.playAndFadeIn()
        let fadeInSteps = await gate.steps - fadeOutSteps

        #expect(fadeOutSteps == 21) // 2 s in 0.1 s steps, plus the wait before the restore
        #expect(fadeInSteps == 30)  // 3 s in 0.1 s steps
    }

    @Test("zero fade times turn fading off")
    func zeroDuration() async throws {
        let player = MockMusicPlayer(state: .playing)
        await player.setVolumeLevel(60)
        let fader = makeFader(player, fadeOut: 0, fadeIn: 0)
        #expect(try await fader.fadeOutAndPause())
        try await fader.playAndFadeIn()
        #expect(await player.commandLog == ["pause", "play"])
    }

    @Test("a cancelled fade-out brings the music back up without pausing")
    func cancelledFadeOut() async throws {
        let player = MockMusicPlayer(state: .playing)
        await player.setVolumeLevel(80)
        let gate = StepGate()
        let fader = makeFader(player, gate: gate)
        await gate.at(step: 8) { await fader.cancel() }

        #expect(try await !fader.fadeOutAndPause())
        #expect(await player.pauseCallCount == 0)
        #expect(await player.volumeLevel == 80)
    }

    @Test("a cancel that comes once the music is paused still sets the user's volume back")
    func cancelAfterPause() async throws {
        let player = MockMusicPlayer(state: .playing, volumeCurve: .cubic)
        await player.setVolumeLevel(60)
        let gate = StepGate()
        let fader = makeFader(player, gate: gate)
        // 20 fade-out steps, then the wait between pausing and setting the volume back.
        await gate.at(step: 21) { await fader.cancel() }

        #expect(try await fader.fadeOutAndPause())
        #expect(await player.pauseCallCount == 1)
        #expect(await player.volumeLevel == 60)
    }

    @Test("pausing without a fade-out mid fade-in still leaves the user's volume")
    func instantPauseDuringFadeIn() async throws {
        let player = MockMusicPlayer(state: .paused, volumeCurve: .cubic)
        await player.setVolumeLevel(70)
        let gate = StepGate()
        let fader = makeFader(player, fadeOut: 0, fadeIn: 3, gate: gate)
        // Another app starts mid fade-in; with no fade-out it pauses at once.
        await gate.at(step: 6) { _ = try? await fader.fadeOutAndPause() }

        try await fader.playAndFadeIn()

        #expect(await player.pauseCallCount == 1)
        #expect(await player.volumeLevel == 70)
    }

    @Test("abandoning a fade sets the user's volume back")
    func abandon() async throws {
        let player = MockMusicPlayer(state: .playing, volumeCurve: .cubic)
        await player.setVolumeLevel(80)
        let gate = StepGate()
        let fader = makeFader(player, gate: gate)
        await gate.at(step: 5) { await fader.abandon() }

        #expect(try await !fader.fadeOutAndPause())
        #expect(await player.volumeLevel == 80)
        #expect(await gate.steps == 5) // set back at once, not faded back up
    }

    @Test("a fade-out that interrupts a fade-in restores the user's volume, not the partly faded one")
    func interruptedFadeIn() async throws {
        let player = MockMusicPlayer(state: .paused)
        await player.setVolumeLevel(70)
        let gate = StepGate()
        let fader = makeFader(player, gate: gate)
        let paused = PausedFlag()
        await gate.at(step: 6) {
            // Another app starts playing while the music fades back in.
            _ = Task { await paused.set(try await fader.fadeOutAndPause()) }
        }

        try await fader.playAndFadeIn()
        await TestWait.until { await paused.value }

        #expect(await paused.value)
        #expect(await player.volumeLevel == 70)
    }
}

private actor PausedFlag {
    private(set) var value = false
    func set(_ value: Bool) { self.value = value }
}

@Suite("VolumeCurve")
struct VolumeCurveTests {
    @Test("a cube law puts half volume at about −18 dB, and converts back")
    func cubic() {
        #expect(abs(VolumeCurve.cubic.decibels(atVolume: 50) - -18.06) < 0.01)
        #expect(abs(VolumeCurve.cubic.volume(atDecibels: -18.06) - 50) < 0.1)
        #expect(VolumeCurve.cubic.decibels(atVolume: 100) == 0)
        #expect(VolumeCurve.cubic.decibels(atVolume: 0) == -.infinity)
    }

    @Test("a linear curve puts half volume at about −6 dB")
    func linear() {
        #expect(abs(VolumeCurve.linear.decibels(atVolume: 50) - -6.02) < 0.01)
    }
}

