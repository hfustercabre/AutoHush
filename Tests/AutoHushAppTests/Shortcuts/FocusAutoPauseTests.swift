import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("FocusAutoPause")
@MainActor
struct FocusAutoPauseTests {
    /// A moment well ahead of the real one, so the settings never clear a
    /// "turn off for" noted here as expired on their own.
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000_000)

    /// The settings and the Focus on one `Preferences`, as in the app; a
    /// second `FocusAutoPause` on it stands for the next launch.
    @MainActor
    private struct Setup {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        let settings: UserSettings
        let focus: FocusAutoPause

        init(now: Date) {
            settings = UserSettings(preferences: preferences, now: now)
            focus = FocusAutoPause(control: settings, preferences: preferences)
        }

        /// The Focus code of the next launch, on the same stored note.
        func relaunched() -> FocusAutoPause {
            FocusAutoPause(control: settings, preferences: preferences)
        }
    }

    @Test("a Focus applies its choice and its end puts the noted Auto-Pause back")
    func appliesAndRestores() {
        let setup = Setup(now: now)
        #expect(setup.settings.isAutoPauseActive)

        setup.focus.follow(false, now: now)
        #expect(!setup.settings.isAutoPauseActive)
        #expect(setup.preferences.focusAutoPause == FocusAutoPauseNote(noted: AutoPauseSetting(), applied: false))

        setup.focus.follow(nil, now: now)
        #expect(setup.settings.isAutoPauseActive)
        #expect(setup.preferences.autoPause == AutoPauseSetting())
        #expect(setup.preferences.focusAutoPause == nil)
    }

    @Test("a timed turn off is noted and comes back to the same end")
    func restoresTimedTurnOff() {
        let setup = Setup(now: now)
        setup.settings.snooze(.thirtyMinutes, now: now)
        let end = AutoPauseSnooze.thirtyMinutes.endDate(from: now)
        #expect(!setup.settings.isAutoPauseActive)

        setup.focus.follow(true, now: now)
        #expect(setup.settings.isAutoPauseActive)
        #expect(setup.preferences.autoPause == AutoPauseSetting(isEnabled: true, snoozedUntil: nil))

        setup.focus.follow(nil, now: now)
        #expect(!setup.settings.isAutoPauseActive)
        #expect(setup.preferences.autoPause == AutoPauseSetting(isEnabled: true, snoozedUntil: end))
    }

    @Test("a timed turn off that ran out during the Focus comes back as on")
    func expiredTurnOffComesBackOn() {
        let setup = Setup(now: now)
        setup.preferences.autoPause = AutoPauseSetting(isEnabled: true, snoozedUntil: now.addingTimeInterval(60))

        setup.focus.follow(true, now: now)
        setup.focus.follow(nil, now: now.addingTimeInterval(120))

        #expect(setup.settings.isAutoPauseActive)
        #expect(setup.preferences.autoPause == AutoPauseSetting())
        #expect(setup.preferences.focusAutoPause == nil)
    }

    @Test("what the user changes during the Focus stands at its end")
    func userChangeStands() {
        let setup = Setup(now: now)
        setup.settings.snooze(.thirtyMinutes, now: now) // the noted state differs from the user's change

        setup.focus.follow(false, now: now)
        setup.settings.setAutoPause(true) // from the menu, during the Focus
        setup.focus.follow(nil, now: now)

        #expect(setup.settings.isAutoPauseActive)
        #expect(setup.preferences.autoPause == AutoPauseSetting(isEnabled: true, snoozedUntil: nil))
        #expect(setup.preferences.focusAutoPause == nil)
    }

    @Test("two Focuses in a row end at the state from before the first")
    func twoFocusesInARow() {
        let setup = Setup(now: now)

        setup.focus.follow(false, now: now)
        #expect(!setup.settings.isAutoPauseActive)
        setup.focus.follow(true, now: now)
        #expect(setup.settings.isAutoPauseActive)
        #expect(setup.preferences.focusAutoPause == FocusAutoPauseNote(noted: AutoPauseSetting(), applied: true))

        setup.focus.follow(nil, now: now)
        #expect(setup.preferences.autoPause == AutoPauseSetting())
        #expect(setup.preferences.focusAutoPause == nil)
    }

    @Test("a Focus's end is still followed after the app was quit during it")
    func noteSurvivesRelaunch() {
        let setup = Setup(now: now)
        setup.focus.follow(false, now: now)

        // The next launch sees the same Focus, then the Focus ends.
        let nextLaunch = setup.relaunched()
        nextLaunch.followAtLaunch(false, now: now)
        #expect(!setup.settings.isAutoPauseActive)
        nextLaunch.follow(nil, now: now)

        #expect(setup.settings.isAutoPauseActive)
        #expect(setup.preferences.focusAutoPause == nil)
    }

    @Test("a Focus that ended while the app was quit is caught at launch")
    func missedEndAtLaunch() {
        let setup = Setup(now: now)
        setup.focus.follow(false, now: now)

        // The launch asks macOS for the active filter: none.
        setup.relaunched().followAtLaunch(nil, now: now)

        #expect(setup.settings.isAutoPauseActive)
        #expect(setup.preferences.focusAutoPause == nil)
    }

    @Test("a Focus that began while the app was quit is caught at launch")
    func missedStartAtLaunch() {
        let setup = Setup(now: now)

        setup.relaunched().followAtLaunch(false, now: now)

        #expect(!setup.settings.isAutoPauseActive)
        #expect(setup.preferences.focusAutoPause == FocusAutoPauseNote(noted: AutoPauseSetting(), applied: false))
    }

    @Test("a launch during a Focus already followed leaves what the user set by hand")
    func launchDuringTheFocus() {
        let setup = Setup(now: now)
        setup.settings.snooze(.thirtyMinutes, now: now) // the noted state differs from the user's change
        setup.focus.follow(false, now: now)
        setup.settings.setAutoPause(true) // from the menu, during the Focus

        let nextLaunch = setup.relaunched()
        nextLaunch.followAtLaunch(false, now: now)
        #expect(setup.settings.isAutoPauseActive)

        nextLaunch.follow(nil, now: now)
        #expect(setup.settings.isAutoPauseActive)
        #expect(setup.preferences.autoPause == AutoPauseSetting(isEnabled: true, snoozedUntil: nil))
        #expect(setup.preferences.focusAutoPause == nil)
    }

    @Test("a launch during another Focus applies its choice, and the end restores the state before the first")
    func launchDuringAnotherFocus() {
        let setup = Setup(now: now)
        setup.settings.snooze(.fifteenMinutes, now: now)
        let end = AutoPauseSnooze.fifteenMinutes.endDate(from: now)
        setup.focus.follow(false, now: now)

        // The first Focus ended and a second one began while the app was quit.
        let nextLaunch = setup.relaunched()
        nextLaunch.followAtLaunch(true, now: now)
        #expect(setup.settings.isAutoPauseActive)

        nextLaunch.follow(nil, now: now)
        #expect(setup.preferences.autoPause == AutoPauseSetting(isEnabled: true, snoozedUntil: end))
        #expect(setup.preferences.focusAutoPause == nil)
    }

    @Test("an end with no note changes nothing")
    func endWithoutNote() {
        let setup = Setup(now: now)
        setup.settings.snooze(.oneHour, now: now)
        let before = setup.preferences.autoPause

        setup.focus.follow(nil, now: now)

        #expect(setup.preferences.autoPause == before)
        #expect(setup.preferences.focusAutoPause == nil)
    }
}
