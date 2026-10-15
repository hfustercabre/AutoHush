import Foundation

/// Checks that a pause or a play took, as Player Check checks each press:
/// the player's state is read until it shows the change, for up to `wait`.
/// One that didn't take is made once more (players press only from the
/// opposite state, so a change that came late isn't undone), then it fails
/// (`pressIgnored`). Not for a player that checks its own presses (a web
/// app's, which mutes one it refuses), nor while the player doesn't answer:
/// nothing can be told then.
package struct PressCheck: Sendable {
    /// How long a press gets to show.
    package static let wait: TimeInterval = 3
    /// How often the state is read meanwhile.
    package static let interval: TimeInterval = 0.1

    let player: any MusicPlayer
    let sleep: VolumeFader.Sleep
    private let logger = AutoHushLogger(category: "VolumeFader")

    package init(player: any MusicPlayer, sleep: @escaping VolumeFader.Sleep) {
        self.player = player
        self.sleep = sleep
    }

    /// Pauses the player (`target` `.paused`) or plays it (`.playing`), and
    /// checks it took.
    package func press(to target: PlayerState) async throws {
        let verb = target == .playing ? "play" : "pause"
        for attempt in 1...2 {
            if target == .playing { try await player.play() } else { try await player.pause() }
            guard !player.checksItsPresses, await !shows(target) else { return }
            logger.notice("[press] \(player.name, privacy: .public) didn't \(verb, privacy: .public) within \(Self.wait, privacy: .public) s\(attempt == 1 ? ": pressing again" : "", privacy: .public)")
        }
        throw MusicPlayerError.playerCommandFailed(.pressIgnored)
    }

    /// Whether the player shows `target` within `wait`: paused or stopped
    /// for a pause, playing for a play. True when it never answers.
    private func shows(_ target: PlayerState) async -> Bool {
        var waited: TimeInterval = 0
        var answered = false
        while true {
            let state = await player.playerState()
            if state != .unknown {
                answered = true
                if target == .playing ? state == .playing : state != .playing { return true }
            }
            guard waited < Self.wait else { return !answered }
            await sleep(Self.interval)
            waited += Self.interval
        }
    }
}
