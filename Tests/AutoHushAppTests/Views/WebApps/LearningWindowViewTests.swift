import AppKit
import SwiftUI
import Testing
@testable import AutoHushApp
@testable import AutoHushKit
import AutoHushTestSupport

/// The learning window, drawn as its window draws it.
@Suite("The learning window, drawn", .waitsTimeLimit)
@MainActor
struct LearningWindowViewTests {
    @Test("with the player's control not allowed, its permission step comes first, with its button; once allowed, it's gone (B-7 of 11-11)")
    func permissionStep() async {
        let status = Locked(OSStatus(errAEEventNotPermitted))
        let center = PermissionCenter(system: .init(
            isTrusted: { true },
            promptAccessibility: {},
            automation: { _, _ in status.value },
            runningPID: { _ in 4242 },
            audio: { .granted },
            requestAudio: { _ in },
            openPane: { _ in }
        ))
        let player = MockMusicPlayer(bundleID: "com.example.jukebox", name: "Jukebox")
        let refresh = { await center.refresh(chosenPlayer: { player }, detectionMethod: .audioLevels, detection: .audioLevel, awaitsReopen: false) }
        await refresh()
        let model = SettingsModel(settings: .inMemory(), updates: FakeUpdateCommands(), permissionCenter: center, actions: FakeAppActions(),
                                  launchAtLoginController: MockLaunchAtLoginController(isEnabled: false),
                                  menuBarIcon: MenuBarIconPlace(defaults: MemoryDefaults()))
        model.state.status.choosePlayer(named: "Jukebox")
        #expect(model.permissions.controlMissing(for: model.chosenPlayerID))
        let control = model.permissions.control ?? .automation(player: "Jukebox")
        let missing = drawn(LearningWindowView(model: model, later: {}), width: AddWebAppView.width, height: 900).height
        let step = drawn(LearningPermissionStep(model: model, permission: control, access: model.permissions.controlAccess, name: "Jukebox"),
                         width: AddWebAppView.width).height
        status.value = noErr
        await refresh()
        #expect(!model.permissions.controlMissing(for: model.chosenPlayerID))
        let allowed = drawn(LearningWindowView(model: model, later: {}), width: AddWebAppView.width, height: 900).height
        // Its title, why, and Allow under them; taller with it on top, though
        // the steps it locks lose their tips.
        #expect(step > 40)
        #expect(missing > allowed, "\(missing) missing, \(allowed) allowed, the step \(step)")
    }
}
