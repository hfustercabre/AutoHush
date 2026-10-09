import Foundation
import Testing
import AutoHushKit
@testable import WebAppPlayers

@Suite("PlayPauseLearner")
struct PlayPauseLearnerTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func look(_ labels: [Int: String]) -> [PageButton] {
        labels.keys.sorted().map { PageButton(handle: ButtonHandle($0), label: labels[$0]!) }
    }

    @Test("the buttons whose words changed between It's Playing and It's Paused are the candidates, with their words the right way round")
    func changedButtons() {
        var learner = PlayPauseLearner()
        #expect(!learner.hasPlayed)
        #expect(learner.candidates(paused: look([1: "Play"])).isEmpty) // nothing noted yet
        learner.notePlaying(look([1: "Pause", 2: "Shuffle", 3: "Pause Song"]), at: start)
        #expect(learner.hasPlayed)
        let candidates = learner.candidates(paused: look([1: "Play", 2: "Shuffle", 3: "Play Song"]))
        #expect(candidates == [
            .init(handle: ButtonHandle(1), playLabel: "Play", pauseLabel: "Pause"),
            .init(handle: ButtonHandle(3), playLabel: "Play Song", pauseLabel: "Pause Song"),
        ])
    }

    @Test("buttons that came or went between the two looks, or have no words, aren't candidates")
    func onlyButtonsInBoth() {
        var learner = PlayPauseLearner()
        learner.notePlaying(look([1: "Pause", 2: "Skip ad", 4: ""]), at: start)
        #expect(learner.candidates(paused: look([1: "Pause", 3: "Play", 4: "Play"])).isEmpty)
    }

    @Test("with an ad first, YouTube Music's bar says Play while it plays: told only once the song itself plays, it's the bar that's learned")
    func afterAnAd() throws {
        var learner = PlayPauseLearner()
        // The song itself plays (the user waited for the ad to end): the bar says Pause.
        learner.notePlaying(look([1: "Pause", 2: "Pause Song"]), at: start)
        let candidates = learner.candidates(paused: look([1: "Play", 2: "Play Song"]))
        let places = [1: Places.playerBar, 2: ButtonPlace(path: ["AXGroup"], distanceFromBottom: 407)]
        let (recipe, handle) = try #require(PlayPauseLearner.recipe(amongAlike: candidates.map {
            ($0, places[$0.handle.element.base as! Int]!)
        }))
        #expect(handle == ButtonHandle(1))
        #expect(recipe.playLabel == "Play" && recipe.pauseLabel == "Pause")
    }

    @Test("It's Playing longer ago than a minute is too late; forgotten, it waits to be told again")
    func tooLate() {
        var learner = PlayPauseLearner()
        learner.notePlaying(look([1: "Pause"]), at: start)
        #expect(!learner.playedTooLongAgo(at: start + LearningStatus.pauseWait))
        #expect(learner.playedTooLongAgo(at: start + LearningStatus.pauseWait + 1))
        learner.forgetPlaying()
        #expect(!learner.hasPlayed)
        #expect(!learner.playedTooLongAgo(at: start + 600))
    }

    @Test("among candidates the barest words win, then the lowest in the window")
    func choosing() throws {
        let bar = PlayPauseLearner.Candidate(handle: ButtonHandle(1), playLabel: "Play", pauseLabel: "Pause")
        let page = PlayPauseLearner.Candidate(handle: ButtonHandle(2), playLabel: "Play", pauseLabel: "Pause")
        let song = PlayPauseLearner.Candidate(handle: ButtonHandle(3), playLabel: "Play Mix", pauseLabel: "Pause Mix")
        let lowSong = ButtonPlace(path: ["AXRow"], distanceFromBottom: 5)
        let (recipe, handle) = try #require(PlayPauseLearner.recipe(amongAlike: [
            (page, Places.main), (song, lowSong), (bar, Places.playerBar),
        ]))
        #expect(handle == ButtonHandle(1))
        #expect(recipe == PlayPauseRecipe(playLabel: "Play", pauseLabel: "Pause", places: [Places.playerBar]))
        #expect(PlayPauseLearner.recipe(amongAlike: []) == nil)
    }

    @Test("SoundCloud: its bar says Play current among the player's controls; its songs' tiles say Play, some out of sight: the bar wins")
    func soundCloud() throws {
        let bar = PlayPauseLearner.Candidate(handle: ButtonHandle(1), playLabel: "Play current", pauseLabel: "Pause current")
        let likedTile = PlayPauseLearner.Candidate(handle: ButtonHandle(2), playLabel: "Play", pauseLabel: "Pause")
        let historyTile = PlayPauseLearner.Candidate(handle: ButtonHandle(3), playLabel: "Play", pauseLabel: "Pause")
        let shownTile = PlayPauseLearner.Candidate(handle: ButtonHandle(4), playLabel: "Play", pauseLabel: "Pause")
        let barPlace = ButtonPlace(path: ["AXGroup:AXLandmarkContentInfo"], distanceFromBottom: 24)
        let sidebar = ButtonPlace(path: ["AXGroup", "AXGroup:AXApplicationGroup"], distanceFromBottom: -77)
        let history = ButtonPlace(path: ["AXGroup", "AXGroup:AXApplicationGroup"], distanceFromBottom: -209)
        let higher = ButtonPlace(path: ["AXGroup", "AXGroup:AXApplicationGroup"], distanceFromBottom: 300)
        let (recipe, handle) = try #require(PlayPauseLearner.recipe(from: [
            (likedTile, sidebar, ButtonStanding(isInWindow: false)),
            (historyTile, history, ButtonStanding(isInWindow: false)),
            (shownTile, higher, ButtonStanding()),
            (bar, barPlace, ButtonStanding(isWithPlayerControls: true)),
        ]))
        #expect(handle == ButtonHandle(1))
        #expect(recipe == PlayPauseRecipe(playLabel: "Play current", pauseLabel: "Pause current", places: [barPlace]))
    }

    @Test("with no candidate in sight or among a player's controls, the barest words and the lowest decide, as before")
    func withoutControls() throws {
        let bar = PlayPauseLearner.Candidate(handle: ButtonHandle(1), playLabel: "Play", pauseLabel: "Pause")
        let song = PlayPauseLearner.Candidate(handle: ButtonHandle(2), playLabel: "Play Mix", pauseLabel: "Pause Mix")
        let outOfSight = ButtonStanding(isInWindow: false)
        let (_, handle) = try #require(PlayPauseLearner.recipe(from: [
            (song, ButtonPlace(path: ["AXRow"], distanceFromBottom: -5), outOfSight),
            (bar, Places.playerBar, outOfSight),
        ]))
        #expect(handle == ButtonHandle(1))
        // In sight beats out of sight even with the barer words out of sight.
        let (_, shown) = try #require(PlayPauseLearner.recipe(from: [
            (song, Places.main, ButtonStanding()), (bar, Places.playerBar, outOfSight),
        ]))
        #expect(shown == ButtonHandle(2))
    }
}
