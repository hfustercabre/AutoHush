import Foundation

/// Checks that a pause or a play took, as Player Check checks each press:
/// the player's state is read until it shows the change, for up to `wait`.
/// One that didn't take is made once more (players press only from the
/// opposite state, so a change that came late isn't undone), then it fails
/// (`pressIgnored`). A toggle judged by another sign is made once only and
/// gets `toggleWait`: its state is read just before it, so a second press
/// would undo a first the app is only slow to show. Not for a player that
/// checks its own presses (a web app's, which mutes one it refuses; an app
/// added through a check, whose ways know which of its signs are sure), nor
/// while the player doesn't answer: nothing can be told then.
package struct PressCheck: Sendable {
    /// How long a press gets to show.
    static let wait: TimeInterval = 3
    /// How long a toggle judged by another sign gets: a streaming player,
    /// played after a long pause, can buffer for seconds before it's heard.
    static let toggleWait: TimeInterval = 10
    /// How often the state is read meanwhile.
    static let interval: TimeInterval = 0.1

    private let name: String
    private let checksItself: Bool
    private let isToggle: Bool
    private let press: @Sendable (PlayerState) async throws -> Void
    private let state: @Sendable () async -> PlayerState
    let sleep: VolumeFader.Sleep
    private let now: @Sendable () -> Date
    private let logger = AutoHushLogger(category: "VolumeFader")

    package init(player: any MusicPlayer, sleep: @escaping VolumeFader.Sleep, now: @escaping @Sendable () -> Date = { Date() }) {
        self.init(name: player.name, checksItself: player.checksItsPresses,
                  press: { target in
                      if target == .playing { try await player.play() } else { try await player.pause() }
                  },
                  state: { await player.playerState() }, sleep: sleep, now: now)
    }

    /// A press made by `press` (to `.paused` or `.playing`), judged by
    /// `state`; `isToggle` for a toggle judged by another sign (see above).
    package init(name: String, checksItself: Bool = false, isToggle: Bool = false,
                 press: @escaping @Sendable (PlayerState) async throws -> Void,
                 state: @escaping @Sendable () async -> PlayerState, sleep: @escaping VolumeFader.Sleep,
                 now: @escaping @Sendable () -> Date = { Date() }) {
        self.name = name
        self.checksItself = checksItself
        self.isToggle = isToggle
        self.press = press
        self.state = state
        self.sleep = sleep
        self.now = now
    }

    /// Pauses the player (`target` `.paused`) or plays it (`.playing`), and
    /// checks it took.
    package func press(to target: PlayerState) async throws {
        let verb = target == .playing ? "play" : "pause"
        let (attempts, wait) = isToggle ? (1, Self.toggleWait) : (2, Self.wait)
        for attempt in 1...attempts {
            try await press(target)
            guard !checksItself, await !shows(target, within: wait) else { return }
            logger.notice("[press] \(self.name, privacy: .public) didn’t \(verb, privacy: .public) within \(wait, privacy: .public) s\(attempt < attempts ? ": pressing again" : "", privacy: .public)")
        }
        throw MusicPlayerError.playerCommandFailed(.pressIgnored)
    }

    /// Whether the player shows `target` within `wait`: paused or stopped
    /// for a pause, playing for a play. True when it never answers. The wait
    /// is measured by the clock, so slow reads count, and by the sleeps
    /// between them (a test's sleep that returns at once still ends it).
    private func shows(_ target: PlayerState, within wait: TimeInterval) async -> Bool {
        let start = now()
        var slept: TimeInterval = 0
        var answered = false
        while true {
            let state = await state()
            if state != .unknown {
                answered = true
                if target == .playing ? state == .playing : state != .playing { return true }
            }
            guard max(now().timeIntervalSince(start), slept) < wait else { return !answered }
            await sleep(Self.interval)
            slept += Self.interval
        }
    }
}
