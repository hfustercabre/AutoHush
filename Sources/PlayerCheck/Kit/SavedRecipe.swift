import WebAppPlayers

/// A learned `PlayPauseRecipe` as the check keeps it between runs: the
/// site's own words for Play and Pause, and the places the button was found.
package struct SavedRecipe: Codable, Equatable, Sendable {
    struct Place: Codable, Equatable, Sendable {
        var path: [String]
        var fromBottom: Double
    }

    var play: String, pause: String, places: [Place]

    package init(_ recipe: PlayPauseRecipe) {
        play = recipe.playLabel
        pause = recipe.pauseLabel
        places = recipe.places.map { Place(path: $0.path, fromBottom: $0.distanceFromBottom) }
    }

    package var recipe: PlayPauseRecipe {
        PlayPauseRecipe(playLabel: play, pauseLabel: pause, places: places.map { ButtonPlace(path: $0.path, distanceFromBottom: $0.fromBottom) })
    }
}
