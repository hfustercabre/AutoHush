import Foundation

/// What Diagnostics shows about the apps with their sound on: how AutoHush
/// judges each one, and what the judgement rests on. The app words it.
package struct ActiveAudioReport: Sendable {
    /// One app with its sound on.
    package struct Entry: Equatable, Sendable {
        /// How AutoHush judges the app.
        package enum State: Sendable {
            /// Counted as playing (its output may have closed since).
            case playing
            /// Audible, but not for long enough to count as playing yet.
            case starting
            /// Its output is open, but it is silent.
            case silent
        }

        /// What the judgement rests on.
        package enum Evidence: Equatable, Sendable {
            /// AntiDot mode: the app tells macOS it is playing.
            case announcing
            /// AntiDot mode: the app told macOS it was playing before, but doesn't now.
            case notAnnouncing
            /// The app's loudest tapped peak (0…1), while audio levels are measured.
            case level(Float)
        }

        package let id: String
        /// The app's name, when it has one other than its ID.
        package let name: String?
        package let state: State
        package let isIgnored: Bool
        package let evidence: Evidence?

        package init(id: String, name: String? = nil, state: State, isIgnored: Bool = false, evidence: Evidence? = nil) {
            self.id = id
            self.name = name
            self.state = state
            self.isIgnored = isIgnored
            self.evidence = evidence
        }
    }

    /// Apps whose processes have their output open.
    var present: Set<String>
    /// Apps counted as playing (they may have closed their output since).
    var playing: Set<String>
    /// Apps audible in the latest check, playing or about to be.
    var audible: Set<String>
    /// Loudest tapped peak (0…1) per app, when audio levels are measured.
    var levels: [String: Float]
    var ignored: Set<String>
    /// AntiDot mode: apps telling macOS they play now, and apps that did before.
    var announcing: Set<String>
    var announcedBefore: Set<String>
    /// The apps' names; an app without one is shown by its ID.
    var sources: [String: AudioSource]

    /// One entry per app, sorted by ID.
    var entries: [Entry] {
        present.union(playing).sorted().map { id in
            Entry(
                id: id,
                name: name(of: id),
                state: playing.contains(id) ? .playing : audible.contains(id) ? .starting : .silent,
                isIgnored: ignored.contains(id),
                evidence: evidence(for: id)
            )
        }
    }

    /// The app's name, unless it is only known by its ID.
    private func name(of id: String) -> String? {
        guard let name = sources[id]?.name, name != id else { return nil }
        return name
    }

    /// What the app tells macOS, or its level.
    private func evidence(for id: String) -> Entry.Evidence? {
        if announcing.contains(id) { return .announcing }
        if announcedBefore.contains(id) { return .notAnnouncing }
        return levels[id].map { .level($0) }
    }
}
