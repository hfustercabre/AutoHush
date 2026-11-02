import AppKit
@testable import CheckedPlayers
import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport
import PlayersTestSupport

extension AppDelegateTests {
    // MARK: - The fix in the alert after the card's line (U2a)

    /// AutoHush's alerts noted with their title, text and buttons, and
    /// answered `answer` (the first button: the fix).
    @MainActor
    private func answering(_ sut: AppDelegate, _ answer: NSApplication.ModalResponse = .alertFirstButtonReturn) -> CallLog {
        let alerts = CallLog()
        sut.runAlert = { alert in
            alerts.calls.append(([alert.messageText, alert.informativeText] + alert.buttons.map(\.title)).joined(separator: " | "))
            return answer
        }
        return alerts
    }

    /// The chosen player's pause failed, `failure` said, while Viewer plays:
    /// the card says "Couldn't pause".
    @MainActor
    private func pauseFailed(_ sut: AppDelegate, _ monitorings: FakeMonitorings, _ failure: ControlFailure) async throws {
        let monitoring = try #require(monitorings.made.last)
        monitoring.send(.activeSources([AudioSource(id: "org.example.viewer", name: "Viewer")]))
        monitoring.send(.playback(.pauseFailed))
        monitoring.send(.pauseFailure(.playerCommandFailed(failure)))
        await TestWait.until { sut.status.alertSituation == .pauseFailed && sut.status.controlError?.failure == failure }
    }

    /// Added, an app added with Add an App, chosen and controlled, Add an
    /// App on its stand-ins, Audio Recording as `audio`.
    @MainActor
    private func addedChosen(audio: AudioCapturePermission? = .granted) async
        -> (scratch: Scratch, sut: AppDelegate, monitorings: FakeMonitorings) {
        let scratch = Scratch()
        let added = AddedApps(scratch.addedSetups)
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { added.players() })
        scratch.installed.insert("com.example.added")
        scratch.addedSetups.save(PlayerSetup(bundleID: "com.example.added", name: "Added",
                                             appURL: URL(fileURLWithPath: "/Applications/com.example.added.app"),
                                             ways: [.menu(menuName: "Controls")]))
        scratch.audio = audio
        let (sut, monitorings) = makeSUT(scratch, chosenPlayer: "com.example.added", addApp: World())
        await start(sut)
        return (scratch, sut, monitorings)
    }

    @MainActor
    @Test("a supported app's failed pause: Try Again (Return) pauses once more")
    func failedPauseTriesAgain() async throws {
        let (sut, monitorings) = makeSUT()
        await start(sut)
        try await pauseFailed(sut, monitorings, .pressIgnored)
        let alerts = answering(sut)
        sut.showControlError()
        #expect(alerts.calls.first?.hasPrefix("Couldn’t Pause First | First didn’t respond to its Play/Pause.") == true)
        #expect(alerts.calls.first?.hasSuffix(" | Try Again | OK") == true)
        #expect(monitorings.made.last?.pauseRetries == 1)
    }

    @MainActor
    @Test("a supported app that answered with an error can't be controlled: no number in the text, and Try Again starts over")
    func cantControlTriesAgain() async {
        let scratch = Scratch()
        await scratch.first.setFailVerify(MusicPlayerError.playerCommandFailed(.appleEventError(-1708)))
        let (sut, _) = makeSUT(scratch)
        sut.session.launch()
        await TestWait.until { sut.status.alertSituation == .cantControl && sut.status.controlError != nil }
        let alerts = answering(sut)
        sut.showControlError()
        #expect(alerts.calls.first?.hasPrefix("Can’t Control First | First answered with an error.") == true)
        #expect(alerts.calls.first?.hasSuffix(" | Try Again | OK") == true)
        #expect(sut.status.health == .starting) // started over, as the card's Try Again does
    }

    @MainActor
    @Test("a supported app's menus changed: Check for Updates (Return) checks, as the menu's Updates does")
    func menusChangedChecksForUpdates() async {
        let scratch = Scratch()
        await scratch.first.setFailVerify(MusicPlayerError.playerCommandFailed(.menuItemNotFound))
        let (sut, _) = makeSUT(scratch, updateChecker: .latestRelease("v0.2.0"))
        let updateAlerts = CallLog()
        sut.updates.showAlert = { $0() }
        sut.updates.runAlert = { alert in
            updateAlerts.calls.append(alert.messageText)
            return .alertFirstButtonReturn
        }
        sut.session.launch()
        await TestWait.until { sut.status.controlError != nil }
        let alerts = answering(sut)
        sut.showControlError()
        #expect(alerts.calls.first?.hasSuffix(" | Check for Updates | OK") == true)
        await TestWait.until { !updateAlerts.calls.isEmpty }
        #expect(updateAlerts.calls == ["AutoHush Is Up to Date"])
    }

    @MainActor
    @Test("a web app that didn't follow its button: Learn Again… (Return) learns it again; its button disabled offers nothing")
    func webAppLearnsAgain() async throws {
        let scratch = Scratch()
        let webApp = scratch.offerWebApp(.learned)
        webApp.setFailVerify(nil) // Accessibility allowed
        let (sut, monitorings) = makeSUT(scratch, chosenPlayer: webApp.bundleID)
        await start(sut)
        #expect(sut.status.learning == .learned)
        try await pauseFailed(sut, monitorings, .buttonDisabled)
        let alerts = answering(sut)
        sut.showControlError()
        // The alert says why, then (unless AutoHush speaks English, which
        // the test runner's bundle decides) the log's English, then AppKit's
        // own OK only.
        let alert = try #require(sut.status.controlErrorAlert())
        #expect(sut.status.controlError?.text.hasSuffix("as during an ad.") == true)
        #expect(alerts.calls.last == "\(alert.title) | \(alert.message) | OK")
        try await pauseFailed(sut, monitorings, .pressFailed)
        sut.showControlError()
        #expect(alerts.calls.last?.hasSuffix(" | Learn Again… | OK") == true)
        await TestWait.until { scratch.learningWindowsMade == 1 }
        #expect(webApp.learnAgainCount == 1)
    }

    @MainActor
    @Test("an added app whose way stopped working: Check Again… (Return) opens Add an App on it")
    func addedAppChecksAgain() async throws {
        let (_, sut, monitorings) = await addedChosen()
        try await pauseFailed(sut, monitorings, .pressIgnored)
        let alerts = answering(sut)
        sut.showControlError()
        #expect(alerts.calls.first?.hasSuffix(" | Check Again… | OK") == true)
        let model = try #require(sut.addApp.model)
        #expect(sut.addApp.window?.isOpen == true)
        await TestWait.until { model.chosen != nil }
        #expect(model.chosen?.url.path == "/Applications/com.example.added.app")
        sut.addApp.window?.close()
    }

    @MainActor
    @Test("an added app that can only be muted, in AntiDot mode: said so, and Turn Off AntiDot Mode (Return) turns it off")
    func mutedOnlyInAntiDotMode() async throws {
        let (_, sut, monitorings) = await addedChosen()
        sut.userSettings.setDetectionMethod(.playbackSignals)
        await TestWait.until { sut.session.settings.detection.isAntiDot }
        try await pauseFailed(sut, monitorings, .muteUnavailable)
        #expect(sut.status.controlError?.text == AntiDotText.onlyMuted("Added"))
        let alerts = answering(sut)
        sut.showControlError()
        #expect(alerts.calls.first?.hasSuffix(" | Turn Off AntiDot Mode | OK") == true)
        #expect(!sut.userSettings.state.detection.isAntiDot)
    }

    @MainActor
    @Test("an added app only its sound tells about, out of AntiDot mode without Audio Recording: AntiDot mode isn't named, and Allow… (Return) asks for it")
    func notHeardWithoutAudioRecording() async throws {
        let (scratch, sut, monitorings) = await addedChosen(audio: .denied)
        await sut.refreshPermissions()
        try await pauseFailed(sut, monitorings, .hearingUnavailable)
        #expect(sut.status.controlError?.text == "AutoHush needs Audio Recording to hear whether Added is playing.")
        let alerts = answering(sut)
        sut.showControlError()
        #expect(alerts.calls.first?.hasSuffix(" | Allow Audio Recording Access… | OK") == true)
        await TestWait.until { scratch.asked.contains("open \(SystemSettingsPane.audioCapture.rawValue)") }
    }

    @MainActor
    @Test("an added app that can only be muted, Audio Recording allowed in System Settings: Reopen AutoHush (Return) reopens it")
    func mutedOnlyReopens() async throws {
        let (_, sut, monitorings) = await addedChosen(audio: .denied)
        sut.noteAudioRecordingAllowedInSettings()
        await sut.refreshPermissions()
        try await pauseFailed(sut, monitorings, .muteUnavailable)
        #expect(sut.status.controlError?.text == "AutoHush can only mute Added, and muting needs Audio Recording.")
        let calls = CallLog()
        sut.openAfterExit = { _ in calls.calls.append("open") }
        sut.terminateToReopen = { calls.calls.append("quit") }
        let alerts = answering(sut)
        sut.showControlError()
        #expect(alerts.calls.first?.hasSuffix(" | Reopen AutoHush | OK") == true)
        #expect(calls.calls == ["open", "quit"])
    }
}
