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
        let (recipe, handle) = try #require(PlayPauseLearner.recipe(from: candidates.map {
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
        let (recipe, handle) = try #require(PlayPauseLearner.recipe(from: [
            (page, Places.main), (song, lowSong), (bar, Places.playerBar),
        ]))
        #expect(handle == ButtonHandle(1))
        #expect(recipe == PlayPauseRecipe(playLabel: "Play", pauseLabel: "Pause", places: [Places.playerBar]))
        #expect(PlayPauseLearner.recipe(from: []) == nil)
    }
}
