import AppKit
import Observation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("PermissionCenter", .waitsTimeLimit)
@MainActor
struct PermissionCenterTests {
    /// A stand-in system: Accessibility, Automation and Audio Recording as set.
    private func center(trusted: Bool = true, automation: OSStatus = noErr, running: Bool = true,
                        audio: AudioCapturePermission? = .granted) -> PermissionCenter {
        PermissionCenter(system: .init(
            isTrusted: { trusted },
            promptAccessibility: {},
            automation: { _, _ in automation },
            runningPID: { _ in running ? 4242 : nil },
            audio: { audio },
            requestAudio: { _ in },
            openPane: { _ in }
        ))
    }

    @Test("Automation's answers: allowed, turned down, never asked, or the player gone")
    func automationAnswers() {
        #expect(PermissionCenter.access(automationStatus: noErr) == .allowed)
        #expect(PermissionCenter.access(automationStatus: OSStatus(errAEEventNotPermitted)) == .denied)
        #expect(PermissionCenter.access(automationStatus: OSStatus(errAEEventWouldRequireUserConsent)) == .notAsked)
        #expect(PermissionCenter.access(automationStatus: OSStatus(procNotFound)) == .playerNotRunning)
    }

    @Test("a scriptable player needs Automation, asked only while it runs; Audio Recording unless in AntiDot mode")
    func scriptablePlayer() async {
        let streamer = MockMusicPlayer(bundleID: "com.example.jukebox", name: "Jukebox")
        let closed = await center(running: false).state(player: streamer, detectionMethod: .audioLevels, detection: .audioLevel, awaitsReopen: false)
        #expect(closed.player == "com.example.jukebox")
        #expect(closed.control == .automation(player: "Jukebox"))
        #expect(closed.controlAccess == .playerNotRunning)
        #expect(closed.audio == .allowed)
        #expect(!closed.allSatisfied)

        let notAsked = await center(automation: OSStatus(errAEEventWouldRequireUserConsent), audio: .notDetermined)
            .state(player: streamer, detectionMethod: .audioLevels, detection: .pending, awaitsReopen: false)
        #expect(notAsked.controlAccess == .notAsked && notAsked.audio == .notAsked)

        let antiDot = await center(audio: .denied).state(player: streamer, detectionMethod: .playbackSignals, detection: .playbackSignals, awaitsReopen: false)
        #expect(antiDot.audio == .notNeeded)
        #expect(antiDot.allSatisfied)
    }

    @Test("Audio Recording switched on in System Settings needs a reopen; unreadable, it follows what monitoring saw")
    func audioRecording() async {
        let denied = await center(audio: .denied).state(player: nil, detectionMethod: .audioLevels, detection: .unavailable, awaitsReopen: false)
        #expect(denied.audio == .denied)
        let reopen = await center(audio: .denied).state(player: nil, detectionMethod: .audioLevels, detection: .unavailable, awaitsReopen: true)
        #expect(reopen.audio == .needsReopen)
        let unreadable = await center(audio: nil).state(player: nil, detectionMethod: .audioLevels, detection: .unavailable, awaitsReopen: false)
        #expect(unreadable.audio == .denied)
        let unreadableFine = await center(audio: nil).state(player: nil, detectionMethod: .audioLevels, detection: .audioLevel, awaitsReopen: false)
        #expect(unreadableFine.audio == .allowed)
    }

    @Test("any app is read by the same rules as the chosen player (Add an App's): Automation while it runs, nothing to read without a control permission")
    func anyApp() async {
        let scripted = await center(automation: OSStatus(errAEEventNotPermitted))
            .state(app: "com.example.radio", control: .automation(player: "Radio"), detectionMethod: .audioLevels,
                   detection: .audioLevel, awaitsReopen: false)
        #expect(scripted.player == "com.example.radio" && scripted.control == .automation(player: "Radio"))
        #expect(scripted.controlAccess == .denied && scripted.audio == .allowed && scripted.accessibility)
        let closed = await center(running: false)
            .state(app: "com.example.radio", control: .automation(player: "Radio"), detectionMethod: .audioLevels,
                   detection: .audioLevel, awaitsReopen: false)
        #expect(closed.controlAccess == .playerNotRunning)
        let unscripted = await center(trusted: false, audio: .notDetermined)
            .state(app: "com.example.radio", control: nil, detectionMethod: .audioLevels, detection: .pending, awaitsReopen: false)
        #expect(unscripted.control == nil && unscripted.controlAccess == .allowed)
        #expect(!unscripted.accessibility && unscripted.audio == .notAsked)
    }

    /// Jukebox and Radio, neither running, and Settings reading the
    /// permissions from the center.
    private func chosenPlayersBench() -> (jukebox: MockMusicPlayer, radio: MockMusicPlayer, sut: PermissionCenter, model: SettingsModel) {
        let jukebox = MockMusicPlayer(bundleID: "com.example.jukebox", name: "Jukebox")
        let radio = MockMusicPlayer(bundleID: "com.example.radio", name: "Radio")
        let sut = center(running: false)
        let model = SettingsModel(settings: .inMemory(), updates: FakeUpdateCommands(), permissionCenter: sut, actions: nil,
                                  launchAtLoginController: MockLaunchAtLoginController(isEnabled: false))
        return (jukebox, radio, sut, model)
    }

    @Test("the chosen player's permissions are kept as last read")
    func keepsTheChosenPlayers() async {
        let (jukebox, _, sut, _) = chosenPlayersBench()
        await sut.refresh(chosenPlayer: { jukebox }, detectionMethod: .audioLevels, detection: .audioLevel, awaitsReopen: false)
        #expect(sut.chosen.player == "com.example.jukebox" && sut.chosen.controlAccess == .playerNotRunning)
    }

    @Test("Settings shows the chosen player's permissions as last read, and follows them")
    func settingsFollowsTheChosenPlayers() async {
        let (jukebox, _, sut, model) = chosenPlayersBench()
        #expect(model.permissions == PermissionsState())
        let changed = Locked(false)
        withObservationTracking { _ = model.permissions } onChange: { changed.value = true }
        await sut.refresh(chosenPlayer: { jukebox }, detectionMethod: .audioLevels, detection: .audioLevel, awaitsReopen: false)
        #expect(model.permissions == sut.chosen && changed.value)
    }

    @Test("a read of the permissions for a player no longer chosen once it's done is dropped")
    func dropsAReadForAnotherPlayer() async {
        let (jukebox, radio, sut, _) = chosenPlayersBench()
        await sut.refresh(chosenPlayer: { jukebox }, detectionMethod: .audioLevels, detection: .audioLevel, awaitsReopen: false)
        // Jukebox chosen again while Radio's read ran: Radio's is dropped.
        var asked = 0
        await sut.refresh(chosenPlayer: {
            asked += 1
            return asked == 1 ? radio : jukebox
        }, detectionMethod: .audioLevels, detection: .audioLevel, awaitsReopen: false)
        #expect(asked == 2 && sut.chosen.player == "com.example.jukebox")
    }

    @Test("a missing control permission counts only as read for that player: the previous player's, read before the switch, doesn't lock the new one's steps")
    func controlMissingForPlayer() {
        let previous = PermissionsState(player: "com.example.jukebox", control: .automation(player: "Jukebox"), controlAccess: .notAsked)
        #expect(previous.controlMissing(for: "com.example.jukebox"))
        #expect(!previous.controlMissing(for: "com.example.webapp"))
        let allowed = PermissionsState(player: "com.example.webapp", control: .accessibility(player: "Web App"), controlAccess: .allowed)
        #expect(!allowed.controlMissing(for: "com.example.webapp"))
        #expect(!PermissionsState().controlMissing(for: nil)) // no player, nothing to control
    }

    @Test("Accessibility, for a web app or adding one, is read as it stands")
    func accessibility() async {
        let state = await center(trusted: false).state(player: nil, detectionMethod: .audioLevels, detection: .audioLevel, awaitsReopen: false)
        #expect(!state.accessibility)
        #expect(state.control == nil && state.controlAccess == .allowed)
    }

    @Test("each missing permission's button does the right thing; Allow for Automation asks macOS about the running player")
    func requests() async {
        let automation = Permission.automation(player: "Jukebox")
        #expect(PermissionCenter.request(for: automation, access: .allowed) == nil)
        #expect(PermissionCenter.request(for: automation, access: .playerNotRunning) == .openPlayer)
        #expect(PermissionCenter.request(for: automation, access: .notAsked) == .askMacOS(automation))
        #expect(PermissionCenter.request(for: automation, access: .denied) == .openSettings(.automation))
        let accessibility = Permission.accessibility(player: "Tides")
        #expect(PermissionCenter.request(for: accessibility, access: .denied) == .askMacOS(accessibility))
        #expect(PermissionCenter.request(for: .systemAudioRecording, access: .notAsked) == .askMacOS(.systemAudioRecording))
        #expect(PermissionCenter.request(for: .systemAudioRecording, access: .denied) == .openSettings(.audioCapture))
        #expect(PermissionCenter.request(for: .systemAudioRecording, access: .needsReopen) == .reopen)
        #expect(PermissionCenter.request(for: .systemAudioRecording, access: .notNeeded) == nil)

        // What Automation's button asks of macOS: about the player as it runs, showing its prompt.
        let asked = CallLog()
        func recording(running: Bool) -> PermissionCenter {
            PermissionCenter(system: .init(
                isTrusted: { true }, promptAccessibility: {},
                automation: { pid, ask in
                    await MainActor.run { asked.calls.append("\(pid) \(ask ? "asking" : "reading")") }
                    return noErr
                },
                runningPID: { _ in running ? 4242 : nil },
                audio: { .granted }, requestAudio: { _ in }, openPane: { _ in }
            ))
        }
        let jukebox = "com.example.jukebox"
        await recording(running: true).perform(.askMacOS(automation), app: jukebox)
        #expect(asked.calls == ["4242 asking"])
        await recording(running: false).perform(.askMacOS(automation), app: jukebox) // nothing to ask about
        await recording(running: true).perform(.openPlayer, app: jukebox)
        await recording(running: true).perform(.reopen, app: jukebox)
        await recording(running: true).perform(.askMacOS(automation), app: nil) // no app
        #expect(asked.calls == ["4242 asking"])
    }
}
