import Foundation
import OSLog

/// Fades a music player's own volume around pausing and playing, so the music
/// eases out and back in instead of stopping and starting abruptly.
///
/// Fades are logarithmic: the level changes by the same number of decibels
/// every step, which is how loudness is heard, between the user's volume and
/// `fadeRange` below it. The player's `VolumeCurve` turns those levels into
/// its volume numbers. A linear ramp on the volume number would sound like it
/// hangs, then drops away at the end (or the reverse, depending on the player).
///
/// Works with any `MusicPlayer` that reports its volume; with one that can't
/// (or with a zero fade time) it simply pauses or plays.
///
/// The user's volume is remembered when a fade starts and set back right after
/// pausing, so the player is never left silent. A fade-in that is interrupted
/// by a new fade-out keeps that remembered volume, rather than the partly
/// faded one.
actor VolumeFader {
    typealias Sleep = @Sendable (TimeInterval) async -> Void

    /// Time between two volume steps.
    static let stepInterval: TimeInterval = 0.1
    /// How far below the user's volume a fade-out ends (before pausing) and a
    /// fade-in starts: practically inaudible next to the music.
    static let fadeRange: Double = 50
    /// Wait after pausing before the volume is set back, so the last of the
    /// player's buffered audio can't blip out at full volume.
    static let restoreDelay: TimeInterval = 0.3

    private let player: any MusicPlayer
    private let curve: VolumeCurve
    private let sleep: Sleep
    private let logger = Logger(category: "VolumeFader")
    private var fadeOut: TimeInterval
    private var fadeIn: TimeInterval
    /// The volume to come back to, while a fade or its restore is under way.
    private var userVolume: Int?
    /// Bumped by every fade and by `cancel()`; a fade stops once it changes.
    private var generation = 0
    /// True while a cancelled fade-out brings the music back up.
    private var isComingBack = false
    /// Set by `abandon()`: fades stop where they are, without coming back.
    private var isAbandoned = false

    init(
        player: any MusicPlayer,
        fadeOut: TimeInterval,
        fadeIn: TimeInterval,
        sleep: @escaping Sleep = { try? await Task.sleep(for: .seconds($0)) }
    ) {
        self.player = player
        self.curve = player.volumeCurve
        self.fadeOut = fadeOut
        self.fadeIn = fadeIn
        self.sleep = sleep
    }

    func setDurations(fadeOut: TimeInterval, fadeIn: TimeInterval) {
        self.fadeOut = fadeOut
        self.fadeIn = fadeIn
    }

    /// Fades the music out, then pauses it. Returns `false` when `cancel()`
    /// stopped the fade first: the music then fades back up and keeps playing.
    func fadeOutAndPause() async throws -> Bool {
        generation += 1
        let fade = generation
        guard fadeOut > 0, let current = await player.volume(), (userVolume ?? current) > 0 else {
            try await player.pause()
            await restoreUserVolume() // e.g. paused at once in the middle of a fade-in
            return true
        }
        let target = userVolume ?? current
        userVolume = target
        let top = level(of: target)
        let bottom = top - Self.fadeRange
        logger.debug("[fade] out from \(current, privacy: .public) (user volume \(target, privacy: .public))")

        guard await ramp(from: level(of: current, floor: bottom), to: bottom, fullTime: fadeOut, fade: fade) else {
            guard !isAbandoned else { return false } // `abandon()` set the volume back
            // Cancelled: bring the music back up from wherever the fade got to.
            let reached = level(of: await player.volume() ?? 0, floor: bottom)
            generation += 1
            isComingBack = true
            defer { isComingBack = false }
            if await ramp(from: reached, to: top, fullTime: fadeIn, fade: generation) {
                userVolume = nil
            }
            return false
        }

        // The user paused it during the fade: it is theirs, not ours to pause.
        switch await player.playerState() {
        case .paused, .stopped, .notRunning:
            await restoreUserVolume()
            return false
        case .playing, .unknown:
            break
        }

        do {
            try await player.pause()
        } catch {
            try? await player.setVolume(target)
            userVolume = nil
            throw error
        }
        await sleep(Self.restoreDelay)
        if generation == fade {
            try? await player.setVolume(target)
            userVolume = nil
        }
        return true
    }

    /// Plays from near silence, then fades the music in to the user's volume.
    func playAndFadeIn() async throws {
        generation += 1
        let fade = generation
        guard fadeIn > 0, let current = await player.volume(), (userVolume ?? current) > 0 else {
            logger.debug("[fade] none: fade-in \(self.fadeIn, privacy: .public) s, volume unknown or off")
            await restoreUserVolume() // e.g. a fade-out interrupted halfway
            try await player.play()
            return
        }
        let target = userVolume ?? current
        userVolume = target
        let top = level(of: target)
        let bottom = top - Self.fadeRange
        logger.debug("[fade] in to \(target, privacy: .public)")

        try? await player.setVolume(volume(at: bottom))
        do {
            try await player.play()
        } catch {
            try? await player.setVolume(target)
            userVolume = nil
            throw error
        }
        if await ramp(from: bottom, to: top, fullTime: fadeIn, fade: fade) {
            userVolume = nil
        }
    }

    /// Stops the fade in progress; a fade-out then comes back up without pausing.
    func cancel() {
        generation += 1
    }

    /// Stops a cancelled fade-out from coming back up, so a new fade-out can
    /// start from where it is. Does nothing otherwise.
    func stopComeback() {
        if isComingBack { generation += 1 }
    }

    /// Stops any fade for good and sets the user's volume back at once, e.g.
    /// when AutoHush quits or restarts monitoring.
    func abandon() async {
        isAbandoned = true
        generation += 1
        await restoreUserVolume()
    }

    private func restoreUserVolume() async {
        guard let volume = userVolume else { return }
        userVolume = nil
        try? await player.setVolume(volume)
    }

    // MARK: - Levels

    /// The level (dB relative to full volume) of a volume number, no lower than `floor`.
    private func level(of volume: Int, floor: Double = -.infinity) -> Double {
        max(curve.decibels(atVolume: Double(volume)), floor)
    }

    /// The nearest volume number for a level.
    private func volume(at level: Double) -> Int {
        min(max(Int(curve.volume(atDecibels: level).rounded()), 0), 100)
    }

    /// Moves the level from `start` to `end` (dB) at a steady rate: covering
    /// the whole `fadeRange` takes `fullTime`, a shorter distance less.
    /// Returns `false` as soon as another fade or `cancel()` takes over.
    private func ramp(from start: Double, to end: Double, fullTime: TimeInterval, fade: Int) async -> Bool {
        let time = fullTime * abs(end - start) / Self.fadeRange
        let steps = max(1, Int((time / Self.stepInterval).rounded()))
        var lastVolume: Int?
        for step in 1...steps {
            await sleep(Self.stepInterval)
            guard generation == fade else { return false }
            let next = volume(at: start + (end - start) * Double(step) / Double(steps))
            if next != lastVolume {
                try? await player.setVolume(next)
                lastVolume = next
            }
        }
        return generation == fade
    }
}
