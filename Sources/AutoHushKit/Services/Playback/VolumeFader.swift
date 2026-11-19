import Foundation

/// Fades a media player's own volume around pausing and playing, so the music
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
/// pausing, so the player is never left silent; after a fade-out whose pause
/// is refused, only once its caller calls `restoreAfterRefusal()`. A fade-in that is interrupted
/// by a new fade-out keeps that remembered volume, rather than the partly
/// faded one.
package actor VolumeFader {
    package typealias Sleep = @Sendable (TimeInterval) async -> Void

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
    /// Each pause and play, checked to have taken.
    private let presses: PressCheck
    /// A pause no mute will stand in for (`pauseNow`).
    private let uncoveredPresses: PressCheck
    private let logger = AutoHushLogger(category: "VolumeFader")
    private var fadeOut: TimeInterval
    private var fadeIn: TimeInterval
    /// The volume to come back to, while a fade or its restore is under way.
    private var userVolume: Int?
    /// Bumped by every fade and by `cancel()`; a fade stops once it changes.
    private var generation = 0
    /// The `generation` the latest fade started with. Unlike `generation` it
    /// ignores `cancel()`, so a pause still gets its volume back.
    private var latestFade = 0
    /// The `generation` of the cancelled fade-out bringing the music back
    /// up, while one does: an older comeback that gives up later leaves a
    /// newer one's alone.
    private var comingBack: Int?
    /// Set by `abandon()`: fades stop where they are, without coming back.
    private var isAbandoned = false
    /// The `generation` of the fade-out under way now (from before its ramp,
    /// while the volume is read), and of the one `cutFadeOutShort()` ended,
    /// which pauses where it got to.
    private var fadingOut: Int?
    private var cutShort: Int?
    /// A fade-out `cancel()` called off that `stopComeback()` reached before
    /// its comeback started: it doesn't come back up (engine-3 of 11-19).
    private var staysDown: Int?
    /// A fade-out called off whose music didn't come back up (it stayed
    /// down, or its comeback was stopped): set back by
    /// `restoreIfLeftDown()` unless a newer fade took the volume over
    /// (R1 of 11-19's diff review).
    private var leftDown: Int?
    /// The fade-out whose pause was refused, its volume left down until
    /// `restoreAfterRefusal`.
    private var refusedFade: Int?

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
        presses = PressCheck(player: player, sleep: sleep)
        uncoveredPresses = PressCheck(player: player, uncovered: true, sleep: sleep)
    }

    func setDurations(fadeOut: TimeInterval, fadeIn: TimeInterval) {
        self.fadeOut = fadeOut
        self.fadeIn = fadeIn
    }

    /// Fades the music out, then pauses it. Returns `false` when `cancel()`
    /// stopped the fade first: the music then fades back up and keeps playing;
    /// or when `abandon()` came before its pause was pressed: it plays on.
    /// Thrown after its ramp (the pause refused), the volume stays down: the
    /// caller must call `restoreAfterRefusal()` once it has muted the player
    /// or found it can't (K1-3 of 11-11).
    func fadeOutAndPause() async throws -> Bool {
        let fade = startFade()
        fadingOut = fade
        guard case let (current, target)? = await fadeVolumes(lasting: fadeOut) else {
            if fadingOut == fade { fadingOut = nil }
            if cutShort == fade { cutShort = nil } // it pauses at once anyway
            guard !isAbandoned else { return false }
            do {
                try await presses.press(to: .paused)
            } catch {
                // Refused: the volume a fade-in under way had reached goes
                // back to the user's, as after a fade-out's (K1-4 of 11-11).
                await restoreUserVolume()
                throw error
            }
            await restoreUserVolume() // e.g. paused at once in the middle of a fade-in
            return true
        }
        let top = level(of: target)
        let bottom = top - Self.fadeRange
        logger.debug("[fade] out from \(current, privacy: .public) (user volume \(target, privacy: .public))")

        // Cut short while the volume was read, it pauses at once, without a ramp.
        var faded = false
        if cutShort != fade {
            faded = await ramp(from: level(of: current, floor: bottom), to: bottom, fullTime: fadeOut, fade: fade)
        }
        if fadingOut == fade { fadingOut = nil } // unless a newer fade-out is under way
        let isCutShort = cutShort == fade
        if isCutShort { cutShort = nil }
        guard faded || isCutShort else {
            guard !isAbandoned else { return false } // `abandon()` set the volume back
            // An app started before it came back up: the next fade-out
            // starts from where it got to.
            if staysDown == fade {
                staysDown = nil
                leftDown = fade
                return false
            }
            // Cancelled: bring the music back up from wherever the fade got to.
            // It comes back from before the volume is read, so an app that
            // starts meanwhile stops it (`stopComeback()`) there already.
            generation += 1
            let comeback = generation
            comingBack = comeback
            defer { if comingBack == comeback { comingBack = nil } }
            let reached = level(of: await player.volume() ?? 0, floor: bottom)
            guard generation == comeback else {
                leftDown = fade // stopped while the volume was read
                return false
            }
            if await ramp(from: reached, to: top, fullTime: fadeIn, fade: comeback) {
                userVolume = nil
            } else {
                leftDown = fade // stopped on its way up
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
        guard !isAbandoned else { return false } // its volume set back already

        do {
            try await presses.press(to: .paused)
        } catch {
            // Refused: the volume stays down until the mute standing in for
            // the pause is made, so the music isn't heard at full volume
            // over the other app meanwhile; the caller sets it back then
            // (`restoreAfterRefusal`; K1-3 of 11-11).
            refusedFade = fade
            throw error
        }
        await sleep(Self.restoreDelay)
        // Unless a newer fade took over the volume meanwhile.
        if latestFade == fade { await restoreUserVolume() }
        return true
    }

    /// Sets the user's volume back after a fade-out whose pause was refused
    /// (`fadeOutAndPause` threw), once its caller made the mute in place of
    /// the pause, or found none could be: unless a newer fade took the
    /// volume over meanwhile. Nothing after any other fade-out.
    func restoreAfterRefusal() async {
        guard let refused = refusedFade else { return }
        refusedFade = nil
        if latestFade == refused { await restoreUserVolume() }
    }

    /// Pauses at once, without a fade, stopping one under way: the output
    /// went away, and a fade would play on the next one; no mute stands in
    /// if it's refused (`pauseUncovered`). The user's volume is set back
    /// after the pause, as after a fade-out.
    func pauseNow() async throws {
        let fade = startFade()
        do {
            try await uncoveredPresses.press(to: .paused)
        } catch {
            // Refused, it plays on: at the user's volume, not where a fade-in
            // under way had got to (K1-4 of 11-11).
            if latestFade == fade { await restoreUserVolume() }
            throw error
        }
        await sleep(Self.restoreDelay)
        if latestFade == fade { await restoreUserVolume() }
    }

    /// Ends the fade-out under way at once: it pauses where it got to,
    /// without fading further (the output went away, and the rest would
    /// play on the next one); one still reading the volume pauses without
    /// fading at all. Nothing while none is. `false` when the
    /// fade-out was called off, the music coming back up instead or about
    /// to (diff-kit-2 of 11-19): no pause comes of it, so it's the caller's
    /// to pause.
    @discardableResult
    func cutFadeOutShort() -> Bool {
        guard comingBack == nil else { return false }
        guard let fadingOut else { return true }
        // Cut short already, it pauses; called off, it won't.
        guard fadingOut == generation else { return cutShort == fadingOut }
        cutShort = fadingOut
        generation += 1
        return true
    }

    /// Sets the user's volume back after a fade-out called off that didn't
    /// come back up (`fadeOutAndPause` returned `false` with an app started
    /// meanwhile), once the pause meant to follow it is over: unless that
    /// pause, or any newer fade, took the volume over. Nothing otherwise.
    func restoreIfLeftDown() async {
        guard let fade = leftDown else { return }
        leftDown = nil
        if latestFade == fade { await restoreUserVolume() }
    }

    /// Pauses at once, without a fade or a volume to set back, checked to
    /// have taken (`PressCheck`): a player muted in place of the pause,
    /// paused for real before its mute is lifted. `uncovered`: no mute will
    /// stand in for it (`pauseUncovered`).
    func pressPause(uncovered: Bool) async throws {
        try await (uncovered ? uncoveredPresses : presses).press(to: .paused)
    }

    /// Plays from near silence, then fades the music in to the user's volume.
    func playAndFadeIn() async throws {
        let fade = startFade()
        guard let target = await fadeVolumes(lasting: fadeIn)?.user else {
            logger.debug("[fade] none: fade-in \(self.fadeIn, privacy: .public) s, volume unknown or off")
            await restoreUserVolume() // e.g. a fade-out interrupted halfway
            try await presses.press(to: .playing)
            return
        }
        // `abandon()` came while the volume was read, before there was one
        // to set back: it plays at once at the user's volume, without a fade
        // (the user, 2026-10-20), rather than from 50 dB down.
        guard !isAbandoned else {
            await restoreUserVolume()
            try await presses.press(to: .playing)
            return
        }
        let top = level(of: target)
        let bottom = top - Self.fadeRange
        logger.debug("[fade] in to \(target, privacy: .public)")

        try? await player.setVolume(volume(at: bottom))
        do {
            try await presses.press(to: .playing)
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
    /// Nothing while a called-off fade-out comes back up already: stopped
    /// there, it would stay partly faded.
    func cancel() {
        if let comingBack, comingBack == generation { return }
        staysDown = nil // called off again: it comes back up after all
        generation += 1
    }

    /// Stops a cancelled fade-out from coming back up, so a new fade-out can
    /// start from where it is, also one called off that hasn't started
    /// coming back yet. Does nothing otherwise.
    func stopComeback() {
        if comingBack == nil, let fadingOut, fadingOut != generation, cutShort != fadingOut {
            staysDown = fadingOut
            return
        }
        guard comingBack != nil else { return }
        comingBack = nil
        generation += 1
    }

    /// Stops any fade for good and sets the user's volume back at once, e.g.
    /// when AutoHush quits or restarts monitoring.
    func abandon() async {
        isAbandoned = true
        generation += 1
        await restoreUserVolume()
    }

    /// Starts a new fade, stopping the one in progress; returns its generation.
    private func startFade() -> Int {
        leftDown = nil // the new fade owns the volume
        generation += 1
        latestFade = generation
        return generation
    }

    /// The volume now and the user's volume to fade from or back to, which is
    /// remembered until the fade ends. `nil` when there is nothing to fade:
    /// no fade time, the volume can't be read, or it is off.
    private func fadeVolumes(lasting duration: TimeInterval) async -> (current: Int, user: Int)? {
        guard duration > 0, let current = await player.volume() else { return nil }
        let user = userVolume ?? current
        guard user > 0 else { return nil }
        userVolume = user
        return (current, user)
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
