import AppKit
import SwiftUI
import Testing
@testable import AutoHushApp
@testable import AutoHushKit
import AutoHushTestSupport

/// The welcome window's second page, "Allow AutoHush to Work", drawn as its
/// window draws it: no other test draws it (the full check, 2026-10-20: its
/// coverage fell to 0 %).
@Suite("The welcome window's permissions, drawn", .waitsTimeLimit)
@MainActor
struct WelcomePermissionsViewTests {
    private let actions = FakeAppActions()

    /// A model whose permissions read as these, for a player chosen by name.
    private func model(automation: OSStatus, audio: AudioCapturePermission?) async -> SettingsModel {
        let center = PermissionCenter(system: .init(
            isTrusted: { true },
            promptAccessibility: {},
            automation: { _, _ in automation },
            runningPID: { _ in 4242 },
            audio: { audio },
            requestAudio: { _ in },
            openPane: { _ in }
        ))
        let player = MockMusicPlayer(bundleID: "com.example.jukebox", name: "Jukebox")
        await center.refresh(chosenPlayer: { player }, detectionMethod: .audioLevels, detection: .audioLevel, awaitsReopen: false)
        let model = SettingsModel(settings: .inMemory(), updates: FakeUpdateCommands(), permissionCenter: center, actions: actions,
                                  launchAtLoginController: MockLaunchAtLoginController(isEnabled: false))
        model.state.status.choosePlayer(named: "Jukebox")
        return model
    }

    @Test("it draws with each permission missing, undecided or allowed", arguments: [
        (OSStatus(errAEEventNotPermitted), AudioCapturePermission?.some(.denied)),
        (OSStatus(errAEEventWouldRequireUserConsent), .some(.notDetermined)),
        (noErr, .some(.granted)),
    ])
    func draws(_ automation: OSStatus, _ audio: AudioCapturePermission?) async {
        let model = await model(automation: automation, audio: audio)
        let size = drawn(WelcomePermissionsView(model: model), width: PlayerChooserView.width)
        #expect(size.height > 0)
    }

    @Test("the welcome window shows it once it asks for permissions")
    func shownByTheWindow() async {
        let model = await model(automation: OSStatus(errAEEventNotPermitted), audio: .denied)
        model.welcomeAsksPermissions = true
        let size = drawn(PlayerChooserView(model: model), width: PlayerChooserView.width)
        #expect(size.height > 0)
    }
}
