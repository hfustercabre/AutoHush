import Foundation
import Testing
@testable import WebAppPlayers

@Suite("PlayPauseLearner")
struct PlayPauseLearnerTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func look(_ labels: [Int: String]) -> [PageButton] {
        labels.keys.sorted().map { PageButton(handle: ButtonHandle($0), label: labels[$0]!) }
    }

    @Test("a button that changes as the sound comes on, then changes back before it goes off, is a candidate")
    func playThenPause() {
        var learner = PlayPauseLearner()
        learner.observe(look([1: "Play", 2: "Shuffle"]), soundIsOn: false, at: start)
        learner.observe(look([1: "Pause", 2: "Shuffle"]), soundIsOn: false, at: start + 1)
        #expect(!learner.hasPlayed)
        learner.observe(look([1: "Pause", 2: "Shuffle"]), soundIsOn: true, at: start + 2)
        #expect(learner.hasPlayed)
        #expect(learner.candidates.isEmpty)
        learner.observe(look([1: "Play", 2: "Shuffle"]), soundIsOn: true, at: start + 5)
        #expect(learner.candidates.isEmpty) // WebKit keeps the sound open a while
        learner.observe(look([1: "Play", 2: "Shuffle"]), soundIsOn: false, at: start + 12)
        #expect(learner.candidates == [.init(handle: ButtonHandle(1), playLabel: "Play", pauseLabel: "Pause")])
    }

    @Test("a button changing back while the music plays on is no stop (YouTube Music's song button)")
    func changeBackWhilePlaying() {
        var learner = PlayPauseLearner()
        learner.observe(look([1: "Reproducir", 2: "Reproducir On The Run"]), soundIsOn: false, at: start)
        learner.observe(look([1: "Pausar", 2: "Pausar On The Run"]), soundIsOn: true, at: start + 1)
        learner.observe(look([1: "Pausar", 2: "Reproducir On The Run"]), soundIsOn: true, at: start + 9)
        learner.observe(look([1: "Pausar", 2: "Reproducir On The Run"]), soundIsOn: true, at: start + 30)
        #expect(learner.candidates.isEmpty)
        // The user pauses: only the player's own button changes back, and the sound goes off.
        learner.observe(look([1: "Reproducir", 2: "Reproducir On The Run"]), soundIsOn: true, at: start + 40)
        learner.observe(look([1: "Reproducir", 2: "Reproducir On The Run"]), soundIsOn: false, at: start + 47)
        #expect(learner.candidates == [.init(handle: ButtonHandle(1), playLabel: "Reproducir", pauseLabel: "Pausar")])
    }

    @Test("a change back long before the sound goes off isn't a stop")
    func farFromTheStop() {
        var learner = PlayPauseLearner()
        learner.observe(look([1: "Play"]), soundIsOn: false, at: start)
        learner.observe(look([1: "Pause"]), soundIsOn: true, at: start + 1)
        learner.observe(look([1: "Play"]), soundIsOn: true, at: start + 2)
        learner.observe(look([1: "Play"]), soundIsOn: false, at: start + 30)
        #expect(learner.candidates.isEmpty)
    }

    @Test("pausing first, then playing, teaches it too")
    func pauseThenPlay() {
        var learner = PlayPauseLearner()
        learner.observe(look([1: "Pausar"]), soundIsOn: true, at: start) // playing already
        learner.observe(look([1: "Reproducir"]), soundIsOn: true, at: start + 1)
        learner.observe(look([1: "Reproducir"]), soundIsOn: false, at: start + 8) // WebKit's output lingers
        #expect(!learner.hasPlayed && learner.candidates.isEmpty)
        learner.observe(look([1: "Pausar"]), soundIsOn: false, at: start + 20)
        learner.observe(look([1: "Pausar"]), soundIsOn: true, at: start + 21)
        #expect(learner.candidates == [.init(handle: ButtonHandle(1), playLabel: "Reproducir", pauseLabel: "Pausar")])
    }

    @Test("a change long before the sound comes on isn't a start")
    func farFromTheSound() {
        var learner = PlayPauseLearner()
        learner.observe(look([1: "Play"]), soundIsOn: false, at: start)
        learner.observe(look([1: "Pause"]), soundIsOn: false, at: start + 1)
        learner.observe(look([1: "Play"]), soundIsOn: false, at: start + 2)
        learner.observe(look([1: "Play"]), soundIsOn: true, at: start + 10)
        #expect(!learner.hasPlayed)
        #expect(learner.candidates.isEmpty)
    }

    @Test("sound that was on from the first look isn't a start")
    func soundAlreadyOn() {
        var learner = PlayPauseLearner()
        learner.observe(look([1: "Play"]), soundIsOn: true, at: start)
        learner.observe(look([1: "Pause"]), soundIsOn: true, at: start + 1)
        learner.observe(look([1: "Play"]), soundIsOn: true, at: start + 2)
        #expect(learner.candidates.isEmpty)
    }

    @Test("nothing is compared across a reload or a closed window")
    func acrossReload() {
        var learner = PlayPauseLearner()
        learner.observe(look([1: "Play"]), soundIsOn: false, at: start)
        learner.observe(nil, soundIsOn: false, at: start + 1)
        learner.observe(look([1: "Pause"]), soundIsOn: true, at: start + 2)
        #expect(!learner.hasPlayed)
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

    @Test("the playing song's own button changing along doesn't win (YouTube Music)")
    func songButton() throws {
        var learner = PlayPauseLearner()
        learner.observe(look([1: "Reproducir", 2: "Reproducir Canción"]), soundIsOn: false, at: start)
        learner.observe(look([1: "Pausar", 2: "Pausar Canción"]), soundIsOn: true, at: start + 1)
        learner.observe(look([1: "Reproducir", 2: "Reproducir Canción"]), soundIsOn: true, at: start + 4)
        learner.observe(look([1: "Reproducir", 2: "Reproducir Canción"]), soundIsOn: false, at: start + 11)
        #expect(learner.candidates.count == 2)
        let places = [1: Places.playerBar, 2: ButtonPlace(path: ["AXGroup"], distanceFromBottom: 0)]
        let (recipe, handle) = try #require(PlayPauseLearner.recipe(from: learner.candidates.map {
            ($0, places[$0.handle.element.base as! Int]!)
        }))
        #expect(handle == ButtonHandle(1))
        #expect(recipe.pauseLabel == "Pausar")
    }
}
