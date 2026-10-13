import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("LearningSession")
@MainActor
struct LearningSessionTests {
    /// A web app AutoHush must learn, whose learning the test moves along.
    private func webApp(_ status: LearningStatus = .learning(hasPlayed: false), id: String = "com.apple.Safari.WebApp.TEST",
                        name: String = "YT Music") -> MockLearningPlayer {
        MockLearningPlayer(bundleID: id, name: name, status: status)
    }

    private func waitFor(_ condition: @MainActor () -> Bool) async {
        await TestWait.until(condition)
    }

    @Test("It's Playing, Pause It Manually and It's Paused go to the player; a click it can't take says why under its step")
    func clicks() async {
        let player = webApp()
        let session = LearningSession(pauseWait: .seconds(60))
        session.follow(player)

        player.answer(playing: .notHeard)
        session.step(.itsPlaying)
        await waitFor { session.state.pause.note == .notHeard }
        #expect(session.state.pause.deadline == nil)

        player.answer(playing: .noted, paused: .nothingChanged)
        session.step(.itsPlaying)
        // AutoHush's own pause didn't take: its step failed, and no minute counts yet.
        await waitFor { session.state.pause.mode == .failed }
        #expect(session.state.status == .learning(hasPlayed: true))
        #expect(session.state.pause.note == nil)
        #expect(session.state.pause.deadline == nil)

        // Pause It Manually: the user has a minute to pause it.
        session.step(.pauseManually)
        await waitFor { session.state.pause.deadline != nil }
        #expect(session.state.pause.mode == .byHand)
        let deadline = session.state.pause.deadline
        #expect(deadline.map { abs($0.timeIntervalSinceNow - 60) < 2 } == true)

        session.step(.itsPaused)
        await waitFor { session.state.pause.note == .nothingChanged }
        #expect(session.state.pause.deadline == deadline) // the minute goes on

        // The page went before It's Paused: back to the first step, saying why.
        player.answer(paused: .cantSeePage)
        session.step(.itsPaused)
        await waitFor { session.state.status == .learning(hasPlayed: false) && session.state.pause.note == .cantSeePage }
        #expect(session.state.pause.deadline == nil)
        #expect(session.state.pause.mode == .automatic)

        player.answer(playing: .noted, paused: .noted)
        session.step(.itsPlaying)
        await waitFor { session.state.pause.mode == .failed }
        session.step(.pauseManually)
        await waitFor { session.state.pause.mode == .byHand }
        session.step(.itsPaused)
        await waitFor { session.state.status == .learned }
        #expect(session.state.pause.note == nil)
        #expect(session.state.pause.deadline == nil)
        #expect(session.state.pause.mode == .byHand) // the steps show the user paused it
    }

    @Test("once AutoHush couldn't pause it: Try Again tries once more; Pause It Manually while it's silent goes back to the first step")
    func afterAFailedPause() async {
        let player = webApp()
        let session = LearningSession()
        session.follow(player)
        session.step(.itsPlaying)
        await waitFor { session.state.pause.mode == .failed }

        // The song stopped meanwhile: back to the first step, saying why.
        player.answer(playing: .notHeard)
        session.step(.pauseManually)
        await waitFor { session.state.status == .learning(hasPlayed: false) }
        #expect(player.restartCount == 1)
        #expect(session.state.pause.note == .notHeard)
        #expect(session.state.pause.mode == .automatic)
        #expect(session.state.pause.deadline == nil)

        player.answer(playing: .noted)
        session.step(.itsPlaying)
        await waitFor { session.state.pause.mode == .failed }
        player.pausesByItself(true)
        session.step(.tryAgain)
        #expect(session.state.pause.mode == .trying)
        await waitFor { session.state.status == .learned }
        #expect(session.state.pause.deadline == nil)
        #expect(session.state.pause.note == nil)
    }

    @Test("It's Playing: AutoHush pauses it itself meanwhile; when that takes, it has learned, with no minute to count")
    func pausesByItself() async {
        let player = webApp()
        let clock = ManualSleep()
        let session = LearningSession(sleep: clock.sleep)
        session.follow(player)
        player.pausesByItself(true)
        session.step(.itsPlaying)
        #expect(session.state.pause.mode == .trying)
        await waitFor { session.state.status == .learned }
        #expect(session.countdown == nil) // no minute counts
        clock.timeIsUp()
        #expect(session.state.pause.mode != .failed)
        #expect(session.state.pause.deadline == nil)
        #expect(session.state.pause.note == nil)
        #expect(player.restartCount == 0)
    }

    @Test("It's Playing while another app is Now Playing: no key, the user pauses it at once, with the minute to count")
    func keyWouldGoElsewhere() async {
        let player = webApp()
        let session = LearningSession(pauseWait: .seconds(60))
        session.follow(player)
        player.keyGoesElsewhere()
        session.step(.itsPlaying)
        await waitFor { session.state.pause.mode == .keyElsewhere }
        await waitFor { session.state.pause.deadline != nil } // its minute counts down
        #expect(session.state.pause.note == nil)
        #expect(session.state.status == .learning(hasPlayed: true))
    }

    @Test("It's Paused as the minute ends: learned, and nothing says the minute went by")
    func pausedAtTheLastMoment() async {
        let player = webApp()
        let clock = ManualSleep()
        let session = LearningSession(sleep: clock.sleep)
        session.follow(player)
        player.learnAtTheLastMoment()
        session.step(.itsPlaying)
        await waitFor { session.state.pause.mode == .failed }
        session.step(.pauseManually)
        clock.timeIsUp() // the minute ends: It's Paused comes just then
        await waitFor { session.state.status == .learned }
        await session.countdown?.value
        #expect(player.restartCount == 0)
        #expect(session.state.pause.note == nil)
    }

    @Test("without It's Paused in time, learning starts over and says why; another player forgets it all")
    func pauseTimesOut() async {
        let player = webApp()
        let clock = ManualSleep()
        let session = LearningSession(pauseWait: .seconds(42), sleep: clock.sleep)
        session.follow(player)
        session.step(.itsPlaying)
        await waitFor { session.state.pause.mode == .failed }
        #expect(session.countdown == nil) // no minute counts until Pause It Manually
        #expect(session.state.status == .learning(hasPlayed: true))
        session.step(.pauseManually)
        await waitFor { clock.durations == [.seconds(42)] } // its minute counts
        clock.timeIsUp()
        await waitFor { session.state.status == .learning(hasPlayed: false) }
        #expect(player.restartCount == 1)
        #expect(session.state.pause.note == .timedOut)
        #expect(session.state.pause.mode == .automatic)
        #expect(session.state.pause.deadline == nil)

        session.follow(nil) // a player that learns nothing
        #expect(session.state == LearningSession.State())
    }

    @Test("another chosen player: what the last one was told goes, and its learning shows as it is")
    func anotherPlayer() async {
        let first = webApp()
        let second = webApp(.learned, id: "com.apple.Safari.WebApp.OTHER", name: "Deezer")
        let session = LearningSession()
        session.follow(first)
        first.answer(playing: .notHeard)
        session.step(.itsPlaying)
        await waitFor { session.state.pause.note == .notHeard }

        session.follow(second)
        #expect(session.state == LearningSession.State(status: .learned, pause: LearningPause()))
    }

    @Test("answers and updates about the player chosen before change nothing for the one chosen now")
    func answersAfterAnotherIsChosen() async {
        let first = webApp()
        let second = webApp(id: "com.apple.Safari.WebApp.OTHER", name: "Deezer")
        let session = LearningSession()
        session.follow(first)
        first.answer(playing: .notHeard)
        session.step(.itsPlaying) // answered once the second one is chosen
        session.follow(second)
        first.set(.learned)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(session.state == LearningSession.State(status: .learning(hasPlayed: false), pause: LearningPause()))

        // Learning again is the chosen one's.
        #expect(await session.learnAgain())
        #expect(second.learnAgainCount == 1 && first.learnAgainCount == 0)
    }
}
