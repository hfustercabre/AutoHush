import Foundation

/// The power assertions an app was seen holding while its sound was on, by
/// name: what AntiDot mode learns about how the app tells macOS it plays.
/// Saved across launches by the app.
package struct AnnouncedAssertions: Equatable, Sendable {
    /// More names than this are not learned: an app naming its assertions
    /// differently each time has nothing to learn from.
    static let namesLimit = 8

    /// Names of assertions that kept the Mac awake.
    package var system: Set<String>
    /// Names of assertions that kept only the display awake.
    package var display: Set<String>

    package init(system: Set<String> = [], display: Set<String> = []) {
        self.system = system
        self.display = display
    }

    /// The app tells macOS when it plays: it kept the Mac awake while its
    /// sound was on.
    var announcesPlayback: Bool { !system.isEmpty }

    /// The app announces only video with sound, through one assertion that
    /// keeps the display awake while the video is visible and the Mac while
    /// it's hidden (measured: WebKit, so Safari). Its sound without video
    /// announces nothing.
    var announcesVideoOnly: Bool { !system.isDisjoint(with: display) }

    /// Adds the names among `assertions`; `true` when one was new.
    mutating func learn(_ assertions: Set<PowerAssertion>) -> Bool {
        var changed = false
        for assertion in assertions {
            switch assertion.kind {
            case .system where system.count < Self.namesLimit:
                changed = system.insert(assertion.name).inserted || changed
            case .display where display.count < Self.namesLimit:
                changed = display.insert(assertion.name).inserted || changed
            default:
                break
            }
        }
        return changed
    }
}

/// AntiDot mode's "What apps tell macOS": judges apps by what they tell macOS
/// instead of by their sound, so nothing is captured.
///
/// An app holding its own "keep the Mac awake" assertion counts as playing.
/// One seen doing that before but not now counts as paused, even with its
/// audio still open. Apps that never did get no verdict here and are judged
/// by their open output instead.
///
/// An app announcing only video (`AnnouncedAssertions.announcesVideoOnly`)
/// also counts as playing while its assertion keeps just the display awake.
/// It counts as paused only after withdrawing its assertion since its sound
/// came on, so its sound without video is judged by its open output, and
/// only for `withdrawalTrust`: its sound still on after that is something
/// else playing, such as audio started right after pausing a video.
struct PlaybackSignals {
    /// How long a video-only announcer withdrawing its assertion counts as a
    /// pause while its sound stays on. WebKit switches its sound off 7.5 s
    /// after a pause (measured on macOS 27).
    static let withdrawalTrust: TimeInterval = 10

    /// What AntiDot mode found in one check.
    struct Judgement: Equatable {
        /// `true` for apps playing, `false` for apps paused; apps without a
        /// verdict are judged by their open output.
        var verdicts: [String: Bool] = [:]
        /// Apps showing a video right now.
        var showingVideo: Set<String> = []
        /// Apps whose learned assertions changed, to be saved.
        var learned: [String: AnnouncedAssertions] = [:]
    }

    private let powerAssertions: (any PowerAssertionReading)?
    /// What each app was seen holding while its sound was on.
    private(set) var learned: [String: AnnouncedAssertions]
    /// When each app last announced playback since its sound came on.
    private var lastAnnounced: [String: Date] = [:]

    init(powerAssertions: (any PowerAssertionReading)?, learned: [String: AnnouncedAssertions]) {
        self.powerAssertions = powerAssertions
        self.learned = learned
    }

    /// The assertions each app among `present` holds right now. `owner`
    /// finds the app a process belongs to (a helper may hold the assertion
    /// for its app, or the app for its helper playing the sound).
    func assertions(among present: Set<String>, owner: (pid_t) -> String?) -> [String: Set<PowerAssertion>] {
        guard let powerAssertions, !present.isEmpty else { return [:] }
        var byApp: [String: Set<PowerAssertion>] = [:]
        for (pid, assertions) in powerAssertions.assertionsByProcess() {
            guard let app = owner(pid), present.contains(app) else { continue }
            byApp[app, default: []].formUnion(assertions)
        }
        return byApp
    }

    /// Forgets which apps announced since their sound came on, e.g. when the
    /// monitor stops: it can't tell what happened meanwhile.
    mutating func forgetAnnouncements() {
        lastAnnounced = [:]
    }

    /// Judges each app among `present` (those with their sound on) by the
    /// assertions it holds, and learns from them.
    mutating func judge(present: Set<String>, holding: [String: Set<PowerAssertion>], at now: Date) -> Judgement {
        lastAnnounced = lastAnnounced.filter { present.contains($0.key) }
        var judgement = Judgement()
        for id in present {
            let held = holding[id] ?? []
            var known = learned[id] ?? AnnouncedAssertions()
            if known.learn(held) {
                learned[id] = known
                judgement.learned[id] = known
            }
            let videoOnly = known.announcesVideoOnly
            let announcing = held.contains { $0.kind == .system || (videoOnly && known.system.contains($0.name)) }
            if held.contains(where: { $0.kind == .display }) || (videoOnly && announcing) {
                judgement.showingVideo.insert(id)
            }
            if announcing {
                lastAnnounced[id] = now
                judgement.verdicts[id] = true
            } else if videoOnly {
                if let last = lastAnnounced[id], now.timeIntervalSince(last) < Self.withdrawalTrust {
                    judgement.verdicts[id] = false
                }
            } else if known.announcesPlayback {
                judgement.verdicts[id] = false
            }
        }
        return judgement
    }
}
