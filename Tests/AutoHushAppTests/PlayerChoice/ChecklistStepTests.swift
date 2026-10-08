import Testing
import AutoHushKit
@testable import AutoHushApp

@MainActor
@Suite("Checklist steps")
struct ChecklistStepTests {
    @Test("VoiceOver reads where each step stands")
    func values() {
        #expect(StepState.done.voiceOverValue == "Completed")
        #expect(StepState.current.voiceOverValue == "In progress")
        #expect(StepState.todo.voiceOverValue == "To do")
    }

    @Test("learning: play is the step to do with It's Playing, then pause with It's Paused and the countdown; locked, neither")
    func learning() {
        let fresh = LearningSteps.steps(name: "YT Music", hasPlayed: false, hasPaused: false, locked: false)
        #expect(fresh.map(\.state) == [.current, .todo])
        #expect(fresh[0].notes == [LearningText.playTip("YT Music")] && fresh[1].notes.isEmpty)
        #expect(fresh.map(\.button) == [.itsPlaying, nil])
        #expect(fresh.currentAnnouncement == "Play a song in YT Music")

        let played = LearningSteps.steps(name: "YT Music", hasPlayed: true, hasPaused: false, locked: false, remaining: 44.2)
        #expect(played.map(\.state) == [.done, .current])
        #expect(played[1].notes == [LearningText.pauseTip, "Back to the first step in 0:45"])
        #expect(played.map(\.button) == [nil, .itsPaused])
        #expect(played.currentAnnouncement == "Pause it")

        let learned = LearningSteps.steps(name: "YT Music", hasPlayed: true, hasPaused: true, locked: false)
        #expect(learned.map(\.state) == [.done, .done])
        #expect(learned.allSatisfy { $0.button == nil })
        #expect(learned.currentAnnouncement == nil)

        let locked = LearningSteps.steps(name: "YT Music", hasPlayed: false, hasPaused: false, locked: true)
        #expect(locked.map(\.state) == [.todo, .todo])
        #expect(locked.allSatisfy { $0.notes.isEmpty && $0.button == nil })
        #expect(locked.currentAnnouncement == nil)
    }

    @Test("a click that couldn't be taken says why under the step it's about")
    func learningNotes() {
        let notHeard = LearningSteps.steps(name: "YT Music", hasPlayed: false, hasPaused: false, locked: false, note: .notHeard)
        #expect(notHeard[0].warning == LearningNote.notHeard.text("YT Music"))
        let timedOut = LearningSteps.steps(name: "YT Music", hasPlayed: false, hasPaused: false, locked: false, note: .timedOut)
        #expect(timedOut[0].warning == LearningNote.timedOut.text("YT Music"))
        let nothing = LearningSteps.steps(name: "YT Music", hasPlayed: true, hasPaused: false, locked: false, note: .nothingChanged)
        #expect(nothing[0].warning == nil)
        #expect(nothing[1].warning == LearningNote.nothingChanged.text("YT Music"))
    }

    @Test("adding a web app: each phase has its step to do, and VoiceOver hears it")
    func adding() {
        #expect(AddWebAppView.steps(for: .checking, learning: nil).map(\.state) == [.current, .todo, .todo, .todo])
        #expect(AddWebAppView.steps(for: .checking, learning: nil).currentAnnouncement == "Check the address")

        let opening = AddWebAppView.steps(for: .opening, learning: nil)
        #expect(opening.map(\.state) == [.done, .current, .todo, .todo])
        #expect(opening[1].notes.count == 1) // the extension tip
        #expect(opening.currentAnnouncement == "Open it in Safari")

        #expect(AddWebAppView.steps(for: .adding, learning: nil).currentAnnouncement == "Add it to the Dock")
    }

    @Test("adding a web app: a site that asks first gets a step of its own, then Add to Dock waits for the click")
    func siteAsksThenAdd() {
        let asks = AddWebAppView.steps(for: .siteAsks(shown: "consent.youtube.com", site: "music.youtube.com"), siteAsked: true,
                                       learning: nil)
        #expect(asks.map(\.title) == ["Check the address", "Open it in Safari", "Answer the site in Safari", "Add it to the Dock",
                                      "Play something in it, then pause it"])
        #expect(asks.map(\.state) == [.done, .done, .current, .todo, .todo])
        #expect(asks.currentAnnouncement == "Answer the site in Safari")

        let ready = AddWebAppView.steps(for: .readyToAdd(site: "music.youtube.com"), siteAsked: true, learning: nil)
        #expect(ready.map(\.state) == [.done, .done, .done, .current, .todo])
        #expect(ready[3].button == .addToDock)

        let readyWithoutAsking = AddWebAppView.steps(for: .readyToAdd(site: "play.qobuz.com"), learning: nil)
        #expect(!readyWithoutAsking.map(\.title).contains("Answer the site in Safari"))
        #expect(AddWebAppView.steps(for: .adding, learning: nil).currentAnnouncement == "Add it to the Dock")
    }

    @Test("adding a web app: once made, the learning window's two steps follow, then all is done")
    func addedAndLearning() {
        let made = AddWebAppModel.Phase.learning(name: "YT Music", alreadyThere: false)
        let toPlay = AddWebAppView.steps(for: made, siteAsked: true, learning: .learning(hasPlayed: false))
        #expect(toPlay.map(\.title) == ["Check the address", "Open it in Safari", "Answer the site in Safari",
                                        "Add it to the Dock as “YT Music”", "Play a song in YT Music", "Pause it"])
        #expect(toPlay.map(\.state) == [.done, .done, .done, .done, .current, .todo])
        #expect(toPlay[4].button == .itsPlaying)

        let toPause = AddWebAppView.steps(for: made, learning: .learning(hasPlayed: true), remaining: 30)
        #expect(toPause.currentAnnouncement == "Pause it")
        #expect(toPause.last?.notes.last == "Back to the first step in 0:30")

        let learned = AddWebAppView.steps(for: made, learning: .learned)
        #expect(learned.allSatisfy { $0.state == .done })
        #expect(learned.currentAnnouncement == nil)

        let already = AddWebAppView.steps(for: .learning(name: "YT Music", alreadyThere: true), learning: .learning(hasPlayed: false))
        #expect(already.map(\.title)[1] == "Already in your Dock as “YT Music”")
        #expect(already.map(\.state) == [.done, .done, .current, .todo])
    }
}
