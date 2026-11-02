import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit

/// The one button that can help in the alert behind the info button after
/// the card's orange line (U2a): by what failed and the kind of player.
@Suite("ControlErrorFix")
struct ControlErrorFixTests {
    private func fix(_ failure: ControlFailure?, _ kind: MusicPlayerKind, _ situation: ControlErrorFix.Situation = .pauseFailed,
                     antiDot: Bool = false, audio: PermissionAccess = .allowed) -> ControlErrorFix? {
        ControlErrorFix.fix(for: failure, kind: kind, situation: situation, antiDot: antiDot, audio: audio)
    }

    @Test("a web app learns its button again when a press didn't work; a button disabled during an ad has no fix")
    func webApp() {
        #expect(fix(.pressIgnored, .safariWebApp) == .learnAgain)
        #expect(fix(.pressFailed, .safariWebApp, .cantControl) == .learnAgain)
        #expect(fix(.buttonDisabled, .safariWebApp) == nil)
    }

    @Test("an app added with Add an App is checked again when its way stopped working")
    func addedAppWays() {
        for failure: ControlFailure in [.pressIgnored, .pressFailed, .menuItemNotFound, .appleEventError(-1708)] {
            #expect(fix(failure, .checkedApp) == .checkAgain, "\(failure)")
            #expect(fix(failure, .checkedApp, .cantControl) == .checkAgain, "\(failure)")
        }
    }

    @Test("an added app that can't be muted or heard: AntiDot mode off, Audio Recording allowed, or AutoHush reopened; none once allowed",
          arguments: [ControlFailure.muteUnavailable, .hearingUnavailable])
    func addedAppNeedsSound(failure: ControlFailure) {
        #expect(fix(failure, .checkedApp, antiDot: true, audio: .notNeeded) == .turnOffAntiDot)
        #expect(fix(failure, .checkedApp, antiDot: true, audio: .denied) == .turnOffAntiDot) // AntiDot mode first
        #expect(fix(failure, .checkedApp, audio: .notAsked) == .allowAudioRecording)
        #expect(fix(failure, .checkedApp, audio: .denied) == .allowAudioRecording)
        #expect(fix(failure, .checkedApp, audio: .needsReopen) == .reopenAutoHush)
        #expect(fix(failure, .checkedApp, audio: .allowed) == nil) // nothing a button changes
    }

    @Test("a supported app tries again (its pause, or starting over), or checks for an update of AutoHush once its menus changed")
    func supportedApp() {
        for failure: ControlFailure in [.pressIgnored, .pressFailed, .appleEventError(-1708)] {
            #expect(fix(failure, .app, .pauseFailed) == .retryPause, "\(failure)")
            #expect(fix(failure, .app, .cantControl) == .retryStart, "\(failure)")
        }
        #expect(fix(.menuItemNotFound, .app) == .checkForUpdates)
        #expect(fix(.menuItemNotFound, .app, .cantControl) == .checkForUpdates)
    }

    @Test("Now Playing hidden opens its pane, and a given-up resume tries again, for any player")
    func everyKind() {
        for kind: MusicPlayerKind in [.app, .safariWebApp, .checkedApp] {
            #expect(fix(.nowPlayingHidden, kind) == .openMenuBarSettings)
            #expect(fix(.nowPlayingHidden, kind, .resumeGivenUp) == .openMenuBarSettings)
            #expect(fix(nil, kind, .resumeGivenUp) == .retryResume)
            #expect(fix(.pressIgnored, kind, .resumeGivenUp) == .retryResume)
        }
    }

    @Test("what nothing can fix keeps OK only: a state that can't be read, nothing to play, an error of no failure, a failure of another kind",
          arguments: [MusicPlayerKind.app, .safariWebApp, .checkedApp])
    func noFix(kind: MusicPlayerKind) {
        #expect(fix(.stateUnknown, kind) == nil)
        #expect(fix(.nothingToPlay, kind) == nil)
        #expect(fix(nil, kind) == nil)
        if kind != .checkedApp {
            #expect(fix(.muteUnavailable, kind, antiDot: true) == nil)
            #expect(fix(.hearingUnavailable, kind, audio: .denied) == nil)
        }
        if kind == .safariWebApp {
            #expect(fix(.menuItemNotFound, kind) == nil)
            #expect(fix(.appleEventError(-1708), kind) == nil)
        }
    }

    @Test("each button says what it does, in the words used elsewhere for the same")
    func titles() {
        #expect(ControlErrorFix.openMenuBarSettings.title == ControlFailure.openMenuBarSettings)
        for retry: ControlErrorFix in [.retryResume, .retryPause, .retryStart] { #expect(retry.title == "Try Again") }
        #expect(ControlErrorFix.checkForUpdates.title == "Check for Updates")
        #expect(ControlErrorFix.learnAgain.title == "Learn Again…")
        #expect(ControlErrorFix.checkAgain.title == "Check Again…")
        #expect(ControlErrorFix.turnOffAntiDot.title == "Turn Off AntiDot Mode")
        #expect(ControlErrorFix.allowAudioRecording.title == "Allow Audio Recording Access…")
        #expect(ControlErrorFix.reopenAutoHush.title == "Reopen AutoHush")
    }
}
