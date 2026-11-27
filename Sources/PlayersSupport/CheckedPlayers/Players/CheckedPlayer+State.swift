import Foundation
import os
import AutoHushKit
import ScriptablePlayers
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
        var pageRead = false
        var sure = await sureState(pid: pid, polled: polled, pageRead: &pageRead)
        // Its page's read lifted its mute (paused for real, the ad over): its
        // signs, read before that pause, are read again (U1 of 11-27: its
        // script's "playing" skipped the resume, the music left paused).
        if !pageRead, await readMutedPage() { sure = await sureState(pid: pid, polled: polled, pageRead: &pageRead) }
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
    /// Now Playing, else its backups' signs; `.unknown` when none answers. Whether its output is open
    /// can't tell: an output stays open for seconds after a pause. Its
    /// presses are checked by this, and a script that only toggles asks it.
    func sureState() async -> PlayerState {
        guard let pid = processIdentifier() else { return .notRunning }
        var pageRead = false
        return await sureState(pid: pid, polled: false, pageRead: &pageRead)
    }

    /// Its page muted in place of a pause, though another sign told its
    /// state first (its script's): read all the same, for its state only it
    /// tells, as only a read of it pauses it for real once it can, lifting
    /// the mute, or lifts one AutoHush no longer holds (`forgetPause`; T2 of
    /// 11-27: its page never read, that mute stayed after the pause).
    /// Whether that read lifted the mute.
    private func readMutedPage() async -> Bool {
        guard let page = parts.page, await page.isMutedForPause() else { return false }
        _ = await page.playerState()
        return await !page.isMutedForPause()
    }

    /// `polled`: read once a second, its sound isn't listened to (the user,
    /// 2026-10-16: else macOS's recording dot stays on all day): one told by
    /// its level goes by its keep-awake assertion then, and a report isn't
    /// checked against its level. `pageRead`: whether its page was read.
    private func sureState(pid: pid_t, polled: Bool, pageRead: inout Bool) async -> PlayerState {
        if let state = await signsSay(parts.signs, pid: pid, polled: polled, pageRead: &pageRead) { return state }
        // Its Now Playing row (and report) doesn't follow it: only its sound
        // tells, and between decisions its keep-awake assertion.
        if parts.hearing != nil {
            if polled {
                let soundOn = soundOn, assertions = assertions
                return await Self.probeQueue.run { assertions.state(of: pid, soundOn: { soundOn(pid) }) }
            }
            return await heardNow(pid).map { $0 ? .playing : .paused } ?? .unknown
        }
        if let reported = await reported(pid: pid, polled: polled) { return reported }
        guard routes else { return .unknown }
        return await signsSay(parts.backupSigns, pid: pid, polled: polled, backups: true, pageRead: &pageRead) ?? .unknown
    }

    /// The first of `signs` that tells its state; a backup's AppleScript is
    /// asked only once Automation for it is allowed, so macOS asks nothing.
    /// `pageRead`: set once its page is read.
    private func signsSay(_ signs: [any MusicPlayer], pid: pid_t, polled: Bool, backups: Bool = false,
                          besidesPage: Bool = false, pageRead: inout Bool) async -> PlayerState? {
        for sign in signs where !(besidesPage && sign is SafariWebAppPlayer) {
            if backups, sign is ScriptedAppPlayer, await !backupAllowed(.script, pid) { continue }
            let state: PlayerState
            if let page = sign as? SafariWebAppPlayer {
                pageRead = true
                state = polled ? await page.polledPlayerState() : await page.playerState()
            } else {
                state = await sign.playerState()
            }
            if state != .unknown { return state }
        }
        return nil
    }

    /// What tells its state while its page's words lag, out of sight: its
    /// other ways' signs (its script's state, its menu's item), what it
    /// reported to Now Playing, else its level (`heardNow`); never whether
    /// its output is open (the user's rule, 2026-10-16); `.unknown` when none
    /// tells. Its page asks it before a press, and after one its words didn't
    /// follow (a minimized Deezer's stay, 2026-11-03).
    func stateBesidesPage() async -> PlayerState {
        guard let pid = processIdentifier() else { return .notRunning }
        var pageRead = false // never: its page asks this
        if let state = await signsSay(parts.signs, pid: pid, polled: false, besidesPage: true, pageRead: &pageRead) { return state }
        if parts.hearing == nil, let reported = await reported(pid: pid, polled: false) { return reported }
        if routes, let state = await signsSay(parts.backupSigns, pid: pid, polled: false, backups: true, besidesPage: true,
                                              pageRead: &pageRead) { return state }
        return await heardNow(pid).map { $0 ? .playing : .paused } ?? .unknown
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
