import CoreAudio
import Foundation

// AudioMonitor: the processes released for their silence, listened to again
// now and then (`quietListenInterval`), and once before a resume
// (`listenToQuietApps`).
extension AudioMonitor {
    /// Where the listens to the quiet processes stand.
    struct QuietListen {
        /// When the quiet processes were last listened to, or released if
        /// not since (`quietListenInterval`); `nil` while there are none.
        var listenedAt: Date?
        /// Until when they're listened to, while they are.
        var until: Date?
        /// The listen under way was asked for (`listenToQuietApps`), so it
        /// goes on while the player doesn't play.
        var asked = false
        /// One of them was heard, or said it plays, during the listen under way.
        var heard = false
        /// Who waits for the listen under way to end (`listenToQuietApps`):
        /// only `endAsk()` takes them, so each is told once.
        private var waiters: [CheckedContinuation<Bool, Never>] = []

        /// `waiter` waits for the listen under way, which is now asked for.
        mutating func wait(_ waiter: CheckedContinuation<Bool, Never>) {
            waiters.append(waiter)
            asked = true
        }

        /// Ends the ask: who waited, to be told whether one was heard.
        mutating func endAsk() -> (waiters: [CheckedContinuation<Bool, Never>], heard: Bool) {
            defer {
                waiters = []
                asked = false
                heard = false
            }
            return (waiters, heard)
        }
    }

    /// Levels are measured, so the quiet processes can be listened to:
    /// never in AntiDot mode, which taps nothing.
    var listensByLevel: Bool { shouldMeterLevels && detectionMode == .audioLevel }

    /// The processes released for their silence that are listened to again:
    /// not an ignored app's, which can't pause the music (R1, the user,
    /// 2026-10-27: else macOS's recording dot showed for it every 30 s).
    var quietProcessesToListen: Set<AudioObjectID> {
        quietProcesses.filter { sourceOfProcess[$0].map { !ignoredSourceIDs.contains($0.id) } ?? false }
    }

    /// Starts and ends the listens to the processes released for their
    /// silence (`quietListenInterval`): only while the player plays, or one
    /// was asked for (`listenToQuietApps`), and levels are measured, so
    /// never in AntiDot mode; a listen ends early once that's over. `true`
    /// when the taps change (one starts or ends).
    func updateQuietListen(at now: Date) -> Bool {
        guard !quietProcessesToListen.isEmpty else {
            quietListen.listenedAt = nil
            quietListen.until = nil
            endQuietListenAsk()
            return false
        }
        let since = quietListen.listenedAt ?? now // released just now
        quietListen.listenedAt = since
        let listens = (playerPlayingSince != nil || quietListen.asked) && listensByLevel
        if let until = quietListen.until {
            guard now >= until || !listens else { return false }
            quietListen.until = nil
            quietListen.listenedAt = now
            endQuietListenAsk()
            return true
        }
        guard listens, now.timeIntervalSince(since) >= Self.quietListenInterval else { return false }
        startQuietListen(at: now)
        return true
    }

    private func startQuietListen(at now: Date) {
        quietListen.until = now.addingTimeInterval(Self.quietListenDuration)
        quietListen.heard = false
        logger.debug("[monitor] listening again to taps released for silence: \(quietProcessesToListen.count, privacy: .public)")
    }

    /// Tells whoever waits for the listen (`listenToQuietApps`) whether one
    /// was heard, as it ends or can't go on.
    func endQuietListenAsk() {
        let (waiters, heard) = quietListen.endAsk()
        for waiter in waiters { waiter.resume(returning: heard) }
    }

    /// Listens once, now, to the processes released for their silence,
    /// whether the player plays or not (R2, the user, 2026-10-27: before
    /// AutoHush resumes it, so a game that plays again with its sound kept
    /// open keeps the music paused): `true` when one is heard, or says it
    /// plays, within `quietListenDuration`, which then counts as playing.
    /// `false` at once with none to listen to (an ignored app's aren't), or
    /// where levels aren't measured (AntiDot mode). One under way: its outcome.
    func listenToQuietApps() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                guard !self.quietProcessesToListen.isEmpty, self.listensByLevel else {
                    continuation.resume(returning: false)
                    return
                }
                self.quietListen.wait(continuation)
                guard self.quietListen.until == nil else { return }
                let now = self.clock()
                self.startQuietListen(at: now)
                self.updateMeteredProcesses(at: now)
            }
        }
    }

    /// Forgets the listens, telling whoever waits that none was heard.
    func resetQuietListen() {
        quietListen.listenedAt = nil
        quietListen.until = nil
        quietListen.heard = false
        endQuietListenAsk()
    }
}
