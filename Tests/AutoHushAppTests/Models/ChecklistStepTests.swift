import AppKit
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
        #expect(StepState.failed.voiceOverValue == "Failed")
    }

    @Test("learning: play is the step to do, with It's Playing")
    func learning() {
        let fresh = LearningSteps.steps(name: "Yodel Music", hasPlayed: false, hasPaused: false, locked: false)
        #expect(fresh.map(\.state) == [.current, .todo])
        #expect(fresh.map(\.title) == ["Play something in Yodel Music", "Let AutoHush pause it"])
        #expect(fresh[0].notes == [LearningText.playTip("Yodel Music")] && fresh[1].notes.isEmpty)
        #expect(fresh.map(\.button) == [.itsPlaying, nil])
        #expect(fresh.currentAnnouncement == "Play something in Yodel Music")
        #expect(fresh.currentTitle == "Play something in Yodel Music") // where VoiceOver's cursor goes
    }

    @Test("learning, to be paused by hand: It's Paused is the step to do, with the countdown")
    func learningPausedByHand() {
        let played = LearningSteps.steps(name: "Yodel Music", hasPlayed: true, hasPaused: false, locked: false, remaining: 44.2,
                                         pauseMode: .byHand)
        #expect(played.map(\.state) == [.done, .failed, .current])
        #expect(played[2].notes == [LearningText.pauseTip])
        #expect(played[2].countdown == "You have 0:45 to pause it and click It’s Paused.")
        #expect(played.map(\.button) == [nil, nil, .itsPaused])
        #expect(played.currentAnnouncement == "Pause it yourself")
        #expect(played.currentTitle == played[2].title) // the one to do, not the one that failed
    }

    @Test("learning, once learned: every step is done, with no button")
    func learningDone() {
        let learned = LearningSteps.steps(name: "Yodel Music", hasPlayed: true, hasPaused: true, locked: false)
        #expect(learned.map(\.state) == [.done, .done])
        #expect(learned.allSatisfy { $0.button == nil })
        #expect(learned.currentAnnouncement == nil)
    }

    @Test("learning, locked: no step to do, VoiceOver hearing the permission and why")
    func learningLocked() {
        let locked = LearningSteps.steps(name: "Yodel Music", hasPlayed: false, hasPaused: false, locked: true)
        #expect(locked.map(\.state) == [.todo, .todo])
        #expect(locked.allSatisfy { $0.notes.isEmpty && $0.button == nil })
        #expect(locked.currentAnnouncement == nil)
        #expect(LearningPermissionStep.announcement(.accessibility(player: "Yodel Music"), name: "Yodel Music")
            == "Allow Accessibility access to control Yodel Music\nAutoHush needs it to see Yodel Music’s buttons. The steps below unlock once it’s allowed.")
    }

    @Test("learning, locked: the permission's step is the one to do now, with its own button, and says what VoiceOver hears")
    func learningPermissionStep() {
        let permission = LearningPermissionStep.step(.accessibility(player: "Yodel Music"), name: "Yodel Music")
        #expect(permission.state == .current && permission.button == nil)
        #expect(([permission.title] + permission.notes).joined(separator: "\n")
            == LearningPermissionStep.announcement(.accessibility(player: "Yodel Music"), name: "Yodel Music"))
    }

    @Test("a click that couldn't be taken says why under the step it's about, and VoiceOver hears it with the step")
    func learningNotes() {
        let notHeard = LearningSteps.steps(name: "Yodel Music", hasPlayed: false, hasPaused: false, locked: false, note: .notHeard)
        #expect(notHeard[0].warning == LearningNote.notHeard.text("Yodel Music"))
        #expect(notHeard.currentAnnouncement == "Play something in Yodel Music\n" + LearningNote.notHeard.text("Yodel Music"))
        let timedOut = LearningSteps.steps(name: "Yodel Music", hasPlayed: false, hasPaused: false, locked: false, note: .timedOut)
        #expect(timedOut[0].warning == LearningNote.timedOut.text("Yodel Music"))
        // It says how long the pause was waited for.
        #expect(LearningNote.timedOut.text("Yodel Music").hasPrefix("A minute went by") && LearningStatus.pauseWait == 60)
        let cantSee = LearningSteps.steps(name: "Yodel Music", hasPlayed: false, hasPaused: false, locked: false, note: .cantSeePage)
        #expect(cantSee[0].warning == LearningNote.cantSeePage.text("Yodel Music"))
        let nothing = LearningSteps.steps(name: "Yodel Music", hasPlayed: true, hasPaused: false, locked: false, note: .nothingChanged,
                                          pauseMode: .byHand)
        #expect(nothing[0].warning == nil)
        #expect(nothing[2].warning == LearningNote.nothingChanged.text("Yodel Music"))
    }

    @Test("AutoHush's pause: a spinner while it tries; failed, Try Again and Pause It Yourself; learned, ticked")
    func learningAutoPause() {
        // Right after It's Playing, before the player says it plays.
        let trying = LearningSteps.steps(name: "Yodel Music", hasPlayed: false, hasPaused: false, locked: false, remaining: 59,
                                         pauseMode: .trying)
        #expect(trying.map(\.state) == [.done, .current])
        #expect(trying[1].isBusy)
        #expect(trying[1].notes == [LearningText.autoPauseTip("Yodel Music")])
        #expect(trying.allSatisfy { $0.button == nil && $0.warning == nil && $0.countdown == nil })

        let failed = LearningSteps.steps(name: "Yodel Music", hasPlayed: true, hasPaused: false, locked: false, pauseMode: .failed)
        #expect(failed.map(\.state) == [.done, .failed])
        #expect(failed[1].warning == LearningText.autoPauseFailed("Yodel Music"))
        #expect(failed[1].button == .tryAgain && failed[1].secondaryButton == .pauseManually)
        #expect(failed.currentAnnouncement == "Let AutoHush pause it\n" + LearningText.autoPauseFailed("Yodel Music"))

        let learned = LearningSteps.steps(name: "Yodel Music", hasPlayed: true, hasPaused: true, locked: false, pauseMode: .trying)
        #expect(learned.map(\.state) == [.done, .done])
        #expect(!learned[1].isBusy)
        let learnedByHand = LearningSteps.steps(name: "Yodel Music", hasPlayed: true, hasPaused: true, locked: false, pauseMode: .byHand)
        #expect(learnedByHand.map(\.state) == [.done, .failed, .done])
        #expect(learnedByHand.allSatisfy { $0.button == nil && $0.countdown == nil })
    }

    @Test("the key would have reached another app: AutoHush's step failed, saying so, and the user's pause comes at once, counting down")
    func learningKeyElsewhere() {
        let steps = LearningSteps.steps(name: "Yodel Music", hasPlayed: true, hasPaused: false, locked: false, remaining: 59,
                                        pauseMode: .keyElsewhere)
        #expect(steps.map(\.state) == [.done, .failed, .current])
        #expect(steps[1].notes == [LearningText.keyElsewhere("Yodel Music")])
        #expect(steps[1].button == nil && steps[1].secondaryButton == nil) // no Try Again: it would go elsewhere again
        #expect(steps[2].button == .itsPaused)
        #expect(steps[2].countdown == "You have 0:59 to pause it and click It’s Paused.")
        #expect(steps.currentAnnouncement == "Pause it yourself")

        let learned = LearningSteps.steps(name: "Yodel Music", hasPlayed: true, hasPaused: true, locked: false, pauseMode: .keyElsewhere)
        #expect(learned.map(\.state) == [.done, .failed, .done])
        #expect(LearningPauseMode.keyElsewhere.pausesByHand && LearningPauseMode.byHand.pausesByHand)
        #expect(!LearningPauseMode.failed.pausesByHand)
    }

    /// The Add window's steps, both groups in order, as the window lists them.
    private func both(_ groups: (adding: [ChecklistStep], learning: [ChecklistStep])) -> [ChecklistStep] {
        groups.adding + groups.learning
    }

    @Test("adding a web app: each phase has its step to do, and VoiceOver hears it")
    func adding() {
        #expect(both(AddWebAppView.stepGroups(for: .checking, learning: nil)).map(\.state) == [.current, .todo, .todo, .todo])
        #expect(both(AddWebAppView.stepGroups(for: .checking, learning: nil)).currentAnnouncement == "Check the address")

        let opening = both(AddWebAppView.stepGroups(for: .opening, learning: nil))
        #expect(opening.map(\.state) == [.done, .current, .todo, .todo])
        #expect(opening[1].notes.count == 1) // the extension tip
        #expect(opening.currentAnnouncement == "Open it in Safari")

        #expect(both(AddWebAppView.stepGroups(for: .adding, learning: nil)).currentAnnouncement == "Add it to the Dock")
    }

    @Test("adding a web app: a site that asks first gets a step of its own, then Add to Dock waits for the click")
    func siteAsksThenAdd() {
        let asks = both(AddWebAppView.stepGroups(for: .siteAsks(shown: "consent.yodel.example", site: "music.yodel.example"),
                                                 siteAsked: true, learning: nil))
        #expect(asks.map(\.title) == ["Check the address", "Open it in Safari", "Answer the site in Safari", "Add it to the Dock",
                                      "Learn its controls"])
        #expect(asks.map(\.state) == [.done, .done, .current, .todo, .todo])
        #expect(asks.currentAnnouncement == "Answer the site in Safari")

        let ready = both(AddWebAppView.stepGroups(for: .readyToAdd(site: "music.yodel.example"), siteAsked: true, learning: nil))
        #expect(ready.map(\.state) == [.done, .done, .done, .current, .todo])
        #expect(ready[3].button == .addToDock)

        let readyWithoutAsking = both(AddWebAppView.stepGroups(for: .readyToAdd(site: "play.quartet.example"), learning: nil))
        #expect(!readyWithoutAsking.map(\.title).contains("Answer the site in Safari"))
        #expect(both(AddWebAppView.stepGroups(for: .adding, learning: nil)).currentAnnouncement == "Add it to the Dock")
    }

    @Test("adding a web app: once made, the learning window's two steps follow, then all is done")
    func addedAndLearning() {
        let made = AddWebAppModel.Phase.learning(name: "Yodel Music", alreadyThere: false)
        let toPlay = both(AddWebAppView.stepGroups(for: made, siteAsked: true, learning: .learning(hasPlayed: false)))
        #expect(toPlay.map(\.title) == ["Check the address", "Open it in Safari", "Answer the site in Safari",
                                        "Add it to the Dock as “Yodel Music”", "Play something in Yodel Music", "Let AutoHush pause it"])
        #expect(toPlay.map(\.state) == [.done, .done, .done, .done, .current, .todo])
        #expect(toPlay[4].button == .itsPlaying)

        let toPause = both(AddWebAppView.stepGroups(for: made, learning: .learning(hasPlayed: true), remaining: 30, pauseMode: .byHand))
        #expect(toPause.currentAnnouncement == "Pause it yourself")
        #expect(toPause.last?.countdown == "You have 0:30 to pause it and click It’s Paused.")

        let learned = both(AddWebAppView.stepGroups(for: made, learning: .learned))
        #expect(learned.allSatisfy { $0.state == .done })
        #expect(learned.currentAnnouncement == nil)

        let locked = both(AddWebAppView.stepGroups(for: made, learning: .learning(hasPlayed: false), locked: true))
        #expect(locked.suffix(2).map(\.state) == [.todo, .todo]) // until Accessibility is allowed
        #expect(locked.allSatisfy { $0.button == nil })

        let already = both(AddWebAppView.stepGroups(for: .learning(name: "Yodel Music", alreadyThere: true),
                                                    learning: .learning(hasPlayed: false)))
        #expect(already.map(\.title)[1] == "Already in your Dock as “Yodel Music”")
        #expect(already.map(\.state) == [.done, .done, .current, .todo])
    }

    @Test("the Add window's steps come in two groups, adding then learning, whatever the number of learning steps")
    func addAndLearnGroups() {
        let made = AddWebAppModel.Phase.learning(name: "Yodel Music", alreadyThere: false)
        let byHand = AddWebAppView.stepGroups(for: made, learning: .learning(hasPlayed: true), pauseMode: .byHand)
        #expect(byHand.adding.last?.title == "Add it to the Dock as “Yodel Music”")
        #expect(byHand.learning.count == 3) // paused by hand: a step more
        #expect(byHand.learning.first?.title == "Play something in Yodel Music")

        let adding = AddWebAppView.stepGroups(for: .adding, learning: nil)
        #expect(adding.learning.isEmpty) // nothing to learn before it's made
        #expect(adding.adding.last?.title == "Learn its controls")

        // Made, but not the chosen player yet: the learning is still the
        // previous player's, so learning it is still the step to do.
        let notChosenYet = AddWebAppView.stepGroups(for: made, madeIsChosen: false, learning: .learned)
        #expect(notChosenYet.learning.map(\.title) == ["Learn its controls"])
        #expect(notChosenYet.learning.map(\.state) == [.current])
    }

    @Test("a step's announcement goes out at high priority, so the focus change that comes with the step doesn't cut it off")
    func announcementPriority() {
        let info = stepAnnouncementInfo("Play something in Yodel Music")
        #expect(info[.announcement] as? String == "Play something in Yodel Music")
        #expect(info[.priority] as? Int == NSAccessibilityPriorityLevel.high.rawValue)
    }
}
