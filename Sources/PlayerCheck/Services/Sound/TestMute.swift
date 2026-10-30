import AutoHushKit
import Foundation

/// Keeps the app silent through a test: its audio processes behind a muted
/// process tap, as AutoHush mutes an app (`ProcessTapMuter`). Its sound
/// still reaches every other tap, so its level is still measured (measured
/// with a player: nothing reached the output while an unmuted tap, and the
/// muting one, heard it at 0.7–0.8). Nothing else it shows changes (its
/// scripted state, what it reports to Now Playing, its page, its keep-awake
/// assertions, its menu, its open output): the app doesn't know. Its
/// processes are looked at every 0.1 s, so one it starts later (an audio
/// service started at its first play) is muted within that (the muter looks
/// again while it's muted); one that has none yet, or that can't be tapped
/// yet, is tried again every half second until it's muted. A tap ends with
/// this tool, so a stop or a crash lets it be heard again too.
/// `@unchecked Sendable`: its mutable state and its muter are touched only
/// on `queue` (`queue.sync`, and the timer that runs there).
final class TestMute: @unchecked Sendable {
    private let pid: pid_t
    private let queue = DispatchQueue(label: "playercheck.mute")
    private var timer: any DispatchSourceTimer?
    private let muter: any AudioMuting
    /// Whether the app has an audio process now; tests stand in for it and the muter.
    private let hasSound: @Sendable (pid_t) -> Bool
    private var muted = false
    /// When processes that couldn't be muted are tried again.
    private var retryAt = Date.distantPast
    /// Whether a mute failed at some point: the app may have been heard.
    private var failed = false

    init(pid: pid_t, muter: any AudioMuting = ProcessTapMuter(recheckInterval: 0.1),
         hasSound: @escaping @Sendable (pid_t) -> Bool = { !OwnedAudioProcesses.objects(ownedBy: $0).isEmpty }) {
        self.pid = pid
        self.muter = muter
        self.hasSound = hasSound
    }

    /// Mutes it once before it returns (so it's silent when the test says
    /// so), then keeps it so; whether it's muted now (true too when it has
    /// no audio process yet).
    func start() -> Bool {
        queue.sync {
            refresh()
            // Muted at once: the muter keeps it so, and nothing is left to retry.
            if !muted {
                let timer = DispatchSource.makeTimerSource(queue: queue)
                timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
                timer.setEventHandler { [weak self] in self?.refresh() }
                self.timer = timer
                timer.resume()
            }
            return muted || !hasSound(pid)
        }
    }

    /// Whether it still looks every 0.1 s for processes to mute: until its
    /// first mute works. For tests (`TestMuteTests`).
    var isRetrying: Bool { queue.sync { timer != nil } }

    /// Until it's muted: the muter keeps it so from then on.
    private func refresh() {
        guard !muted, Date() >= retryAt, hasSound(pid) else { return }
        guard muter.mute(appPID: pid) else {
            failed = true
            retryAt = Date().addingTimeInterval(0.5)
            return
        }
        muted = true
        timer?.cancel()
        timer = nil
    }

    /// Lets it be heard again; whether a mute failed meanwhile.
    func stop() -> Bool {
        queue.sync {
            timer?.cancel()
            timer = nil
            muter.unmute(appPID: pid)
            muted = false
            return failed || (muter as? ProcessTapMuter)?.missedSome == true
        }
    }
}
