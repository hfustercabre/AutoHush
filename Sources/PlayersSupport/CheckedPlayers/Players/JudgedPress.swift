import AutoHushKit

/// A press by one of an added app's ways, then its Now Playing panel row
/// judged by it (K4-1 of 11-11): kept once the press took, let go when it
/// failed, left as its song, name or memory told when nothing answered (a
/// check whose state never answered, which `PressCheck` lets pass: the
/// second diff review's D1). `CheckedPlayer` and `BackedUpPlayer` press
/// alike but for when a press goes through the check (S-3 of 1.4.2's review).
enum JudgedPress {
    /// By `way` toward `target`: as it is, or, `throughCheck`, through
    /// `PressCheck` by `state`. Judged when `way` checks its own presses or
    /// the press went through the check.
    static func press(_ way: any MusicPlayer, to target: PlayerState, throughCheck: Bool, name: String,
                      state: @escaping @Sendable () async -> PlayerState, sleep: @escaping VolumeFader.Sleep) async throws {
        let panel = way as? PanelWay
        do {
            if throughCheck {
                try await PressCheck(name: "\(name) (\(type(of: way)))",
                                     press: { target in if target == .playing { try await way.play() } else { try await way.pause() } },
                                     state: state, sleep: sleep).press(to: target)
            } else if target == .playing {
                try await way.play()
            } else {
                try await way.pause()
            }
        } catch {
            await panel?.pressJudged(false)
            throw error
        }
        guard let panel else { return }
        let judged = way.checksItsPresses || throughCheck
        var answered = judged && way.checksItsPresses
        if judged, !answered { answered = await state() != .unknown }
        await panel.pressJudged(answered ? true : nil)
    }
}
