import Foundation
import AutoHushKit

/// Learns which of a web app's buttons plays and pauses it from two looks at
/// its page, each taken when the user says so: while the song itself plays
/// ("It's Playing"), and once they've paused it ("It's Paused"). The button
/// whose words changed between the two is the one: what it said while the
/// music played is its pause words, what it says after is its play words.
///
/// Nothing is guessed from the app's sound, so what made watching unreliable
/// doesn't matter: an ad before the song (YouTube Music's bar says "Play"
/// meanwhile), a player bar that comes only once something plays, a Mac slow
/// to read the page.
///
/// Other buttons can change along: the playing song's own ("Pause <song>"
/// becomes "Play <song>"), a playlist's. So among the candidates it keeps
/// those with the barest words (dropping "Play X" when there's a "Play"),
/// then the lowest in the window: players keep their controls at the bottom
/// (measured on YouTube Music, Amazon Music and Spotify).
package struct PlayPauseLearner {
    /// A button whose words changed between the two looks.
    package struct Candidate: Equatable, Sendable {
        package let handle: ButtonHandle
        package let playLabel: String
        package let pauseLabel: String
    }

    /// Each button's words while the music played, and when the user said it
    /// played.
    private var playing: (labels: [ButtonHandle: String], at: Date)?

    package init() {}

    /// The user said it plays, and the look was taken.
    package var hasPlayed: Bool { playing != nil }

    /// Takes the look while the music plays.
    package mutating func notePlaying(_ buttons: [PageButton], at now: Date) {
        let labels = buttons.filter { !$0.label.isEmpty }.map { ($0.handle, $0.label) }
        playing = (Dictionary(labels, uniquingKeysWith: { first, _ in first }), now)
    }

    /// Forgets that look: the user starts over.
    package mutating func forgetPlaying() {
        playing = nil
    }

    /// The look while it played is older than `LearningStatus.pauseWait`.
    package func playedTooLongAgo(at now: Date) -> Bool {
        guard let playing else { return false }
        return now.timeIntervalSince(playing.at) > LearningStatus.pauseWait
    }

    /// The buttons whose words changed since it played, in the page's order.
    package func candidates(paused buttons: [PageButton]) -> [Candidate] {
        guard let playing else { return [] }
        var seen: Set<ButtonHandle> = []
        return buttons.compactMap { button in
            guard seen.insert(button.handle).inserted, !button.label.isEmpty,
                  let before = playing.labels[button.handle], before != button.label else { return nil }
            return Candidate(handle: button.handle, playLabel: button.label, pauseLabel: before)
        }
    }

    /// The candidate to keep, as a recipe: the barest words, then the lowest
    /// in the window. `nil` without one.
    package static func recipe(from candidates: [(Candidate, ButtonPlace)]) -> (PlayPauseRecipe, ButtonHandle)? {
        let bare = candidates.filter { candidate, _ in
            !candidates.contains { other, _ in
                other.playLabel != candidate.playLabel && candidate.playLabel.hasPrefix(other.playLabel)
            }
        }
        guard let (chosen, place) = bare.min(by: { $0.1.distanceFromBottom < $1.1.distanceFromBottom }) else { return nil }
        return (PlayPauseRecipe(playLabel: chosen.playLabel, pauseLabel: chosen.pauseLabel, places: [place]), chosen.handle)
    }
}
