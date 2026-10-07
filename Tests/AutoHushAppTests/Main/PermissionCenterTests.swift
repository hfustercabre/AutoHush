import AppKit
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("PermissionCenter")
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
        let spotify = MockMusicPlayer(bundleID: "com.example.jukebox", name: "Jukebox")
        let closed = await center(running: false).state(player: spotify, detectionMethod: .audioLevels, detection: .audioLevel, awaitsReopen: false)
        #expect(closed.control == .automation(player: "Jukebox"))
        #expect(closed.controlAccess == .playerNotRunning)
        #expect(closed.audio == .allowed)
        #expect(!closed.allSatisfied)

        let notAsked = await center(automation: OSStatus(errAEEventWouldRequireUserConsent), audio: .notDetermined)
            .state(player: spotify, detectionMethod: .audioLevels, detection: .pending, awaitsReopen: false)
        #expect(notAsked.controlAccess == .notAsked && notAsked.audio == .notAsked)

        let antiDot = await center(audio: .denied).state(player: spotify, detectionMethod: .playbackSignals, detection: .playbackSignals, awaitsReopen: false)
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

    @Test("Accessibility, for a web app or adding one, is read as it stands")
    func accessibility() async {
        let state = await center(trusted: false).state(player: nil, detectionMethod: .audioLevels, detection: .audioLevel, awaitsReopen: false)
        #expect(!state.accessibility)
        #expect(state.control == nil && state.controlAccess == .allowed)
    }

    @Test("each missing permission's button does the right thing")
    func requests() {
        let automation = Permission.automation(player: "Jukebox")
        #expect(PermissionCenter.request(for: automation, access: .allowed) == nil)
        #expect(PermissionCenter.request(for: automation, access: .playerNotRunning) == .openPlayer)
        #expect(PermissionCenter.request(for: automation, access: .notAsked) == .askMacOS(automation))
        #expect(PermissionCenter.request(for: automation, access: .denied) == .openSettings(.automation))
        let accessibility = Permission.accessibility(player: "TIDAL")
        #expect(PermissionCenter.request(for: accessibility, access: .denied) == .askMacOS(accessibility))
        #expect(PermissionCenter.request(for: .systemAudioRecording, access: .notAsked) == .askMacOS(.systemAudioRecording))
        #expect(PermissionCenter.request(for: .systemAudioRecording, access: .denied) == .openSettings(.audioCapture))
        #expect(PermissionCenter.request(for: .systemAudioRecording, access: .needsReopen) == .reopen)
        #expect(PermissionCenter.request(for: .systemAudioRecording, access: .notNeeded) == nil)
    }
}
