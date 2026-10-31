import Foundation
import os
import AutoHushKit
import WebAppPlayers

// CheckedPlayer: its state, from its sure signs, its level and its reports.
extension CheckedPlayer {
    /// Asked when AutoHush is about to pause or play it (and as it starts):
    /// its level may be listened to then.
    package func playerState() async -> PlayerState {
        await state(polled: false)
    }

    /// For its observer, about once a second: its page is read as a web
    /// app's observer reads it (less often while it's silent), and its sound
    /// is never listened to (see `sureState`).
    func polledState() async -> PlayerState {
        await state(polled: true)
    }

    private func state(polled: Bool) async -> PlayerState {
        guard let pid = processIdentifier() else { return .notRunning }
        let sure = await sureState(pid: pid, polled: polled)
        if sure != .unknown { return sure }
        // Told by its level, which isn't listened to now: an open output
        // tells nothing (Qobuz keeps its own open while paused).
        let soundIsOn = await soundOnNow(pid)
        if polled, parts.hearing != nil { return soundIsOn ? .unknown : .paused }
        return soundIsOn ? .playing : .paused
    }

    /// Only its sure signs tell (`sureState`); one told by its sound alone
    /// (`parts.hearing`) never states itself.
    package func statesItself() async -> Bool {
        guard parts.hearing == nil else { return false }
        return await sureState() != .unknown
    }

    /// Whether its sound output is on, read on the probe's queue, never on
    /// Swift's shared threads (DEVELOPMENT.md).
    func soundOnNow(_ pid: pid_t) async -> Bool {
        let soundOn = soundOn
        return await Self.probeQueue.run { soundOn(pid) }
    }

    /// What its sure signs say: its ways' own (its script's state, its
    /// page's word, its menu's item), else, for one whose Now Playing row
    /// doesn't follow it, its level (`heardNow`), else what it reported to
    /// Now Playing; `.unknown` when none answers. Whether its output is open
    /// can't tell: an output stays open for seconds after a pause. Its
    /// presses are checked by this, and a script that only toggles asks it.
    func sureState() async -> PlayerState {
        guard let pid = processIdentifier() else { return .notRunning }
        return await sureState(pid: pid, polled: false)
    }

    /// `polled`: read once a second, its sound isn't listened to (the user,
    /// 2026-10-16: else macOS's recording dot stays on all day): one told by
    /// its level goes by its keep-awake assertion then, and a report isn't
    /// checked against its level.
    private func sureState(pid: pid_t, polled: Bool) async -> PlayerState {
        for sign in parts.signs {
            let state: PlayerState
            if polled, let page = sign as? SafariWebAppPlayer {
                state = await page.polledPlayerState()
            } else {
                state = await sign.playerState()
            }
            if state != .unknown { return state }
        }
        // Its Now Playing row (and report) doesn't follow it: only its sound
        // tells, and between decisions its keep-awake assertion.
        if parts.hearing != nil {
            if polled {
                let soundOn = soundOn, assertions = assertions
                return await Self.probeQueue.run { assertions.state(of: pid, soundOn: { soundOn(pid) }) }
            }
            return await heardNow(pid).map { $0 ? .playing : .paused } ?? .unknown
        }
        return await reported(pid: pid, polled: polled) ?? .unknown
    }

    /// Whether it's heard now, by its level (half a second of listening),
    /// only when AutoHush is about to pause or play it, or checks a press:
    /// one with no sound output open isn't; `nil` without Audio Recording
    /// or in AntiDot mode, which taps no sound.
    func heardNow(_ pid: pid_t) async -> Bool? {
        guard await soundOnNow(pid) else { return false }
        guard tapsAllowed.withLock({ $0 }) else { return nil }
        // Audio Recording asked on the probe's queue too: TCC answers by IPC.
        let probe = levelProbe, allowed = audioRecordingAllowed
        return await Self.probeQueue.run { allowed() ? probe.isAudible(appPID: pid) : nil }
    }
}
