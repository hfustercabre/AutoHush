import Foundation
import AutoHushKit

/// How to find a web app's Play/Pause button, learned by watching the user
/// play and pause it once (`PlayPauseLearner`).
package struct PlayPauseRecipe: Equatable, Sendable {
    /// What the button says while the music is paused, e.g. "Play" or
    /// "Reproducir": the site's own word, in its language.
    package let playLabel: String
    /// What it says while the music plays, e.g. "Pause".
    package let pauseLabel: String
    /// Where it is: one place for each layout of the site learned, the
    /// latest first.
    package let places: [ButtonPlace]

    /// A site may show its player in more than one layout (a full-screen
    /// view, say); each one learned is kept, up to this many.
    package static let placeLimit = 3

    package init(playLabel: String, pauseLabel: String, places: [ButtonPlace]) {
        self.playLabel = playLabel
        self.pauseLabel = pauseLabel
        self.places = places
    }

    /// The music's state as the button shows it; `nil` for a label of
    /// neither kind (not the button any more).
    package func state(of button: PageButton) -> PlayerState? {
        switch button.label {
        case pauseLabel: .playing
        case playLabel: .paused
        default: nil
        }
    }

    /// The button among `buttons`: one saying either word, at a learned place
    /// (the same elements around it), the closest to that place's distance
    /// from the bottom. Never one somewhere else: another button saying
    /// "Play" (a playlist's) would start other music.
    package func find(in buttons: [PageButton], place: (ButtonHandle) -> ButtonPlace?) -> PageButton? {
        let labelled = buttons.filter { state(of: $0) != nil }
        let placed = labelled.compactMap { button in place(button.handle).map { (button, $0) } }
        for learned in places {
            let matching = placed.filter { $0.1.path == learned.path }
            if let best = matching.min(by: {
                abs($0.1.distanceFromBottom - learned.distanceFromBottom) < abs($1.1.distanceFromBottom - learned.distanceFromBottom)
            }) {
                return best.0
            }
        }
        return nil
    }

    /// What it knows after learning `newer`: with the same words, the new
    /// place too (first); with other words (the site changed language), only
    /// what's new.
    package func merging(_ newer: PlayPauseRecipe) -> PlayPauseRecipe {
        guard newer.playLabel == playLabel, newer.pauseLabel == pauseLabel else { return newer }
        let kept = places.filter { place in !newer.places.contains { $0.path == place.path } }
        return PlayPauseRecipe(playLabel: playLabel, pauseLabel: pauseLabel,
                               places: Array((newer.places + kept).prefix(Self.placeLimit)))
    }
}

// MARK: - Storage

extension PlayPauseRecipe {
    /// As a property list, for `UserDefaults`.
    var propertyList: [String: Any] {
        [
            "play": playLabel,
            "pause": pauseLabel,
            "places": places.map { ["path": $0.path, "fromBottom": $0.distanceFromBottom] as [String: Any] },
        ]
    }

    init?(propertyList: [String: Any]) {
        guard let play = propertyList["play"] as? String, let pause = propertyList["pause"] as? String,
              let stored = propertyList["places"] as? [[String: Any]]
        else { return nil }
        let places = stored.compactMap { place -> ButtonPlace? in
            guard let path = place["path"] as? [String], let distance = place["fromBottom"] as? Double else { return nil }
            return ButtonPlace(path: path, distanceFromBottom: distance)
        }
        guard !places.isEmpty else { return nil }
        self.init(playLabel: play, pauseLabel: pause, places: places)
    }
}

/// Where each web app's recipe is kept. A protocol, so tests keep theirs in
/// memory.
package protocol PlayPauseRecipeStore: Sendable {
    func recipe(for bundleID: String) -> PlayPauseRecipe?
    func save(_ recipe: PlayPauseRecipe, for bundleID: String)
}

/// The recipes in AutoHush's preferences, by the web app's bundle ID. Read
/// and written from the players' own queues: `UserDefaults` is thread-safe.
package struct DefaultsRecipeStore: PlayPauseRecipeStore {
    package static let key = Preferences.webAppButtonsKey

    package init() {}

    package func recipe(for bundleID: String) -> PlayPauseRecipe? {
        let stored = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: [String: Any]]
        return stored?[bundleID].flatMap(PlayPauseRecipe.init(propertyList:))
    }

    /// Under `Preferences.webAppButtonsLock`: another web app may be saving
    /// its own, or old ones being cleared out, at the same time.
    package func save(_ recipe: PlayPauseRecipe, for bundleID: String) {
        Preferences.webAppButtonsLock.withLockUnchecked {
            var stored = UserDefaults.standard.dictionary(forKey: Self.key) ?? [:]
            stored[bundleID] = recipe.propertyList
            UserDefaults.standard.set(stored, forKey: Self.key)
        }
    }
}
