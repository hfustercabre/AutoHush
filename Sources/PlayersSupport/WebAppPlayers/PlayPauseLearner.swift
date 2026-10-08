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
///   3. a change back shortly before the sound went off (or just after: a
///      page can update its words a moment late) is a stop, once the sound
///      has stayed off a few seconds or the button changed again: music that
///      comes back by itself (a stall, the gap between an ad and the song)
///      wasn't paused;
///   4. a button with a start and a stop (in either order: the user may
///      pause first) is a candidate.
/// A change back while the music plays on isn't a stop: YouTube Music turns
/// the playing song's own button back to "Play <song>" by itself (measured).
/// Two more kinds of start, both measured on a fresh YouTube Music window,
/// which shows its player bar only once something plays:
///   - a button that comes onto the page as the sound comes on, already
///     saying "Pause";
///   - a change while the sound is on, before the stop: with an ad first, the
///     bar comes saying "Play" and turns to "Pause" only once the song
///     itself begins, the sound on all along.
/// The stop is the button's last change before the sound went off (else its
/// first one just after), and gives the words: what it said before is
/// "Pause", after is "Play".
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

    /// One button's words changing between two looks; from no words, it came
    /// onto the page.
    private struct Change {
        let handle: ButtonHandle
        let from: String
        let to: String
        let at: Date
        /// The app's sound was on at that look.
        let soundOn: Bool
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
    /// How long the sound has to stay off for a stop to count, unless the
    /// button changes meanwhile: music that comes back by itself (a stall,
    /// the gap between an ad and the song) wasn't paused.
    static let stopSettle: TimeInterval = 3
    /// Changes older than this are forgotten.
    static let memory: TimeInterval = 600
    /// At most this many changes are kept: a page can change a lot of words.
    static let changeLimit = 500

    /// The words of each button at the last look.
    private var previous: [ButtonHandle: String] = [:]
    private var changes: [Change] = []
    /// Buttons that came onto the page in the last few seconds, until a
    /// sound start shows they came with the music or they're too old to have.
    private var arrivals: [Change] = []
    /// The arrivals that came with the music: starts.
    private var arrivedStarts: [Change] = []
    /// When the app's sound came on, and when it went off.
    private var soundStarts: [Date] = []
    private var soundStops: [Date] = []
    private var soundWasOn: Bool?
    private var lastLook: Date?

    package init() {}

    /// The sound came on with a button changing (or coming): the user played
    /// the app.
    package var hasPlayed: Bool { !arrivedStarts.isEmpty || changes.contains(where: isNearSoundStart) }

    /// Takes one look at the page (`nil` while the app has no window).
    package mutating func observe(_ buttons: [PageButton]?, soundIsOn: Bool, at now: Date) {
        if soundWasOn == false, soundIsOn { soundStarts.append(now) }
        if soundWasOn == true, !soundIsOn { soundStops.append(now) }
        soundWasOn = soundIsOn
        lastLook = now
        guard let buttons else {
            previous = [:] // its next page is new
            return
        }
        // On a page's first look, every button is new: none came.
        let comparable = !previous.isEmpty
        for button in buttons where !button.label.isEmpty {
            if let before = previous[button.handle] {
                if before != button.label, !before.isEmpty {
                    changes.append(Change(handle: button.handle, from: before, to: button.label, at: now, soundOn: soundIsOn))
                }
            } else if comparable {
                arrivals.append(Change(handle: button.handle, from: "", to: button.label, at: now, soundOn: soundIsOn))
            }
        }
        previous = Dictionary(buttons.map { ($0.handle, $0.label) }, uniquingKeysWith: { first, _ in first })
        arrivedStarts += arrivals.filter(isNearSoundStart)
        // A sound start can come at most `startWindow.upperBound` after.
        arrivals = arrivals.filter { !isNearSoundStart($0) && now.timeIntervalSince($0.at) <= Self.startWindow.upperBound }
        Self.forgetOld(&changes, now: now)
        Self.forgetOld(&arrivedStarts, now: now)
        soundStarts.removeAll { now.timeIntervalSince($0) > Self.memory }
        soundStops.removeAll { now.timeIntervalSince($0) > Self.memory }
    }

    private static func forgetOld(_ changes: inout [Change], now: Date) {
        changes.removeAll { now.timeIntervalSince($0.at) > memory }
        if changes.count > changeLimit { changes.removeFirst(changes.count - changeLimit) }
    }

    private func isNearSoundStart(_ change: Change) -> Bool {
        soundStarts.contains { Self.startWindow.contains($0.timeIntervalSince(change.at)) }
    }

    /// What may have been the button's pause, for each time the sound went
    /// off (newest first): its last change up to `stopWindow.upperBound`
    /// before, then its first one just after (a page can update its words a
    /// moment late). Only stops that `settled`.
    private func pauses(in own: [Change]) -> [Change] {
        soundStops.reversed().filter { settled($0, own) }.flatMap { stop in
            [
                own.last { (0...Self.stopWindow.upperBound).contains(stop.timeIntervalSince($0.at)) },
                own.first { (Self.stopWindow.lowerBound..<0).contains(stop.timeIntervalSince($0.at)) },
            ].compactMap { $0 }
        }
    }

    /// Whether the sound stayed off `stopSettle` after a stop (until it came
    /// back, or until the last look), or the button changed meanwhile: the
    /// user paused rather than the music stopping a moment by itself.
    private func settled(_ stop: Date, _ own: [Change]) -> Bool {
        let end = soundStarts.first { $0 > stop } ?? lastLook ?? stop
        return end.timeIntervalSince(stop) >= Self.stopSettle || own.contains { $0.at > stop && $0.at <= end }
    }

    /// The buttons whose pause had a matching start: the opposite change
    /// close to the sound coming on (in either order: the user may pause
    /// first) or while it was on before the pause, or the button coming onto
    /// the page with the sound, saying what it said before the pause. The
    /// pause gives the words: what it said before is the pause button's,
    /// after is the play button's. Taking the last change before the sound
    /// went off keeps an earlier change from passing for the pause: with an
    /// ad first, YouTube Music's bar turns to "Pause" as the song begins,
    /// and a pause right after would otherwise swap the words (measured).
    package var candidates: [Candidate] {
        let arrivalsOf = Dictionary(grouping: arrivedStarts, by: \.handle)
        let changesOf = Dictionary(grouping: changes, by: \.handle)
        // In the page's order, so candidates that started together keep it.
        var seen: Set<ButtonHandle> = []
        let handles = changes.map(\.handle).filter { seen.insert($0).inserted }
        var found: [(candidate: Candidate, start: Date)] = []
        for handle in handles {
            let own = changesOf[handle] ?? []
            for pause in pauses(in: own) {
                let start = own.first { change in
                    change.from == pause.to && change.to == pause.from
                        && (isNearSoundStart(change) || (change.soundOn && change.at < pause.at))
                } ?? arrivalsOf[handle]?.first { $0.to == pause.from && $0.at < pause.at }
                guard let start else { continue }
                found.append((Candidate(handle: handle, playLabel: pause.to, pauseLabel: pause.from), start.at))
                break
            }
        }
        return found.enumerated()
            .sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }
            .map(\.element.candidate)
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
