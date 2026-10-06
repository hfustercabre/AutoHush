import Foundation

/// Learns which of a web app's buttons plays and pauses it, by watching the
/// user play and pause it once. Fed a look at the page about every second.
///
/// A play/pause button changes what it says ("Play" ↔ "Pause") each time the
/// music starts or stops. The app's sound comes on within about a second of
/// a start, and goes off within seconds of a stop (YouTube Music keeps it
/// open about 7 s). So:
///   1. between looks, it notes every button whose words changed;
///   2. a change close to the moment the sound came on is a start: its new
///      words are the button's while the music plays;
///   3. a change back shortly before the sound went off is a stop;
///   4. a button with a start and a stop (in either order: the user may
///      pause first) is a candidate.
/// A change back while the music plays on isn't a stop: YouTube Music turns
/// the playing song's own button back to "Play <song>" by itself (measured).
/// Other buttons can change too: the playing song's own ("Pause <song>"), a
/// playlist's ("Play <playlist>"), a page's big Play. So among candidates it
/// keeps those with the barest words (dropping "Play X" when there's a
/// "Play"), then the lowest in the window: players keep their controls at the
/// bottom (measured on YouTube Music, Amazon Music and Spotify).
package struct PlayPauseLearner {
    /// A button that matches its play and pause words.
    package struct Candidate: Equatable, Sendable {
        package let handle: ButtonHandle
        package let playLabel: String
        package let pauseLabel: String
    }

    /// One button's words changing between two looks.
    private struct Change {
        let handle: ButtonHandle
        let from: String
        let to: String
        let at: Date
    }

    /// From the look that saw a change to the one that saw the sound come on,
    /// for the change to count as a start. Looks are a second apart, and the
    /// sound can take a moment more while the music loads.
    static let startWindow: ClosedRange<TimeInterval> = -1.5...3.5
    /// From the look that saw a change back to the one that saw the sound go
    /// off, for it to count as a stop: WebKit keeps the sound open for up to
    /// 7.5 s after a pause (measured on YouTube Music; Amazon Music and
    /// Spotify about 2 s).
    static let stopWindow: ClosedRange<TimeInterval> = -1.5...12
    /// Changes older than this are forgotten.
    static let memory: TimeInterval = 600
    /// At most this many changes are kept: a page can change a lot of words.
    static let changeLimit = 500

    /// The words of each button at the last look.
    private var previous: [ButtonHandle: String] = [:]
    private var changes: [Change] = []
    /// When the app's sound came on, and when it went off.
    private var soundStarts: [Date] = []
    private var soundStops: [Date] = []
    private var soundWasOn: Bool?

    package init() {}

    /// A start was seen: the user played the app.
    package var hasPlayed: Bool { !starts.isEmpty }

    /// Takes one look at the page (`nil` while the app has no window).
    package mutating func observe(_ buttons: [PageButton]?, soundIsOn: Bool, at now: Date) {
        if soundWasOn == false, soundIsOn { soundStarts.append(now) }
        if soundWasOn == true, !soundIsOn { soundStops.append(now) }
        soundWasOn = soundIsOn
        guard let buttons else {
            previous = [:] // its next page is new
            return
        }
        for button in buttons {
            if let before = previous[button.handle], before != button.label, !before.isEmpty, !button.label.isEmpty {
                changes.append(Change(handle: button.handle, from: before, to: button.label, at: now))
            }
        }
        previous = Dictionary(buttons.map { ($0.handle, $0.label) }, uniquingKeysWith: { first, _ in first })
        changes.removeAll { now.timeIntervalSince($0.at) > Self.memory }
        if changes.count > Self.changeLimit { changes.removeFirst(changes.count - Self.changeLimit) }
        soundStarts.removeAll { now.timeIntervalSince($0) > Self.memory }
        soundStops.removeAll { now.timeIntervalSince($0) > Self.memory }
    }

    /// Each button's first start: its words before and after.
    private var starts: [ButtonHandle: Change] {
        var starts: [ButtonHandle: Change] = [:]
        for change in changes where starts[change.handle] == nil {
            if soundStarts.contains(where: { Self.startWindow.contains($0.timeIntervalSince(change.at)) }) {
                starts[change.handle] = change
            }
        }
        return starts
    }

    /// The buttons that changed at a start, and changed back at a stop.
    package var candidates: [Candidate] {
        starts.values.sorted { $0.at < $1.at }.compactMap { start in
            let changedBack = changes.contains { change in
                change.handle == start.handle && change.from == start.to && change.to == start.from
                    && soundStops.contains { Self.stopWindow.contains($0.timeIntervalSince(change.at)) }
            }
            return changedBack ? Candidate(handle: start.handle, playLabel: start.from, pauseLabel: start.to) : nil
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
