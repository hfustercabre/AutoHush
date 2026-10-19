import AppKit
import CheckedPlayers
import Foundation
import os
import SwiftUI
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport
import PlayersTestSupport

extension AppDelegateTests {
    // MARK: - Permissions in the windows

    @MainActor
    @Test("a web app chosen in the welcome window is learned once the welcome window is done, or closed")
    func welcomeThenLearning() {
        let scratch = Scratch()
        scratch.installed = [Players.first]
        let webApp = scratch.offerWebApp(.learning(hasPlayed: false))
        let (sut, _) = makeSUT(scratch, chosenPlayer: nil)
        sut.handleApplicationDidLaunch(bundleIdentifier: Players.first) // brings the welcome window
        #expect(sut.isShowingPlayerChooser)

        sut.chooseMusicPlayer(webApp.bundleID)
        #expect(sut.settingsModel.welcomeAsksPermissions)
        #expect(!scratch.learningWindow.isOpen) // waits for the welcome window

        scratch.chooser.close() // closed instead of Done: the same
        sut.followWelcomeClosed()
        #expect(!sut.settingsModel.welcomeAsksPermissions)
        #expect(scratch.learningWindow.isOpen)
    }

    @MainActor
    @Test("the windows learn what's missing: the player's control permission, Audio Recording unless in AntiDot mode")
    func permissionsFollowed() async {
        let scratch = Scratch()
        scratch.automationStatus = OSStatus(errAEEventNotPermitted)
        scratch.audio = .denied
        let (sut, _) = makeSUT(scratch)
        await sut.refreshPermissions()
        #expect(sut.settingsModel.permissions.control == .automation(player: "First"))
        #expect(sut.settingsModel.permissions.controlAccess == .playerNotRunning)
        #expect(sut.settingsModel.permissions.audio == .denied)
        #expect(!sut.settingsModel.permissions.allSatisfied)

        scratch.running = [Players.first]
        await sut.refreshPermissions()
        #expect(sut.settingsModel.permissions.controlAccess == .denied)

        sut.settingsModel.useAntiDotMode()
        await sut.refreshPermissions()
        #expect(sut.settingsModel.permissions.audio == .notNeeded)
    }

    @MainActor
    @Test("a slow read of the permissions for the player chosen before, finishing after the new player's, doesn't replace the new one's")
    func stalePermissionsDropped() async {
        let scratch = Scratch()
        scratch.running = [Players.first] // its Automation is asked, and is slow
        let (sut, _) = makeSUT(scratch)
        await scratch.automationGate.close()
        let slow = Task { await sut.refreshPermissions() }
        await TestWait.until { await scratch.automationGate.waiting == 1 }
        sut.chooseMusicPlayer(Players.second)
        await sut.refreshPermissions()
        #expect(sut.settingsModel.permissions.control == .automation(player: "Second"))
        await scratch.automationGate.open()
        await slow.value
        #expect(sut.settingsModel.permissions.control == .automation(player: "Second"))
    }

    @MainActor
    @Test("a missing permission's button opens the player, asks macOS, or opens System Settings, as it stands; only Audio Recording allowed there offers to reopen AutoHush")
    func permissionRequests() async {
        let scratch = Scratch()
        scratch.automationStatus = OSStatus(errAEEventNotPermitted)
        scratch.audio = .denied
        let (sut, _) = makeSUT(scratch)

        // Automation with the player closed: the button opens it.
        sut.requestPermission(.automation(player: "First"))
        await TestWait.until { !scratch.opened.isEmpty }
        #expect(scratch.opened.map(\.lastPathComponent) == ["\(Players.first).app"])

        // Automation turned down, the player running: System Settings, and no reopen is offered.
        scratch.running = [Players.first]
        sut.requestPermission(.automation(player: "First"))
        await TestWait.until { !scratch.asked.isEmpty }
        #expect(scratch.asked == ["open Privacy_Automation"])
        #expect(!sut.status.awaitsReopenForAudioRecording)

        // Accessibility (Add a Web App's Allow…): macOS's prompt, then System Settings.
        scratch.trusted = false
        sut.addWebAppModel.openAccessibilitySettings()
        await TestWait.until { scratch.asked.count == 3 }
        #expect(scratch.asked.suffix(2) == ["prompt accessibility", "open Privacy_Accessibility"])

        // Audio Recording turned down: System Settings, then AutoHush is to be reopened.
        sut.requestPermission(.systemAudioRecording)
        await TestWait.until { scratch.asked.count == 4 }
        #expect(scratch.asked.last == "open Privacy_AudioCapture")
        #expect(sut.status.awaitsReopenForAudioRecording)
        await sut.refreshPermissions()
        #expect(sut.settingsModel.permissions.audio == .needsReopen)

        // Never asked: macOS's own prompt.
        scratch.audio = .notDetermined
        sut.requestPermission(.systemAudioRecording)
        await TestWait.until { scratch.asked.count == 5 }
        #expect(scratch.asked.last == "ask audio")
    }

    /// The app Add an App checks, and AutoHush with Automation turned down.
    @MainActor
    private func addAppPermissionsBench() -> (scratch: Scratch, sut: AppDelegate, app: CheckableApp) {
        let scratch = Scratch()
        scratch.automationStatus = OSStatus(errAEEventNotPermitted)
        let (sut, _) = makeSUT(scratch)
        return (scratch, sut, CheckableApp(bundleID: "com.example.radio", name: "Radio", url: URL(filePath: "/Applications/Radio.app")))
    }

    @MainActor
    @Test("Add an App reads Automation for its app while the app runs, and only for one it scripts")
    func addAppReadsAutomation() async {
        let (scratch, sut, app) = addAppPermissionsBench()
        // Scripted and closed: Automation waits for it to run. Not scripted: no Automation.
        #expect(await sut.checkPermissions(app, scriptable: true) == CheckPermissions(accessibility: true, audio: .allowed, automation: .playerNotRunning))
        #expect(await sut.checkPermissions(app, scriptable: false).automation == nil)
        scratch.running = [app.bundleID]
        #expect(await sut.checkPermissions(app, scriptable: true).automation == .denied)
    }

    @MainActor
    @Test("Add an App reads Audio Recording, when macOS can't tell about it, by what monitoring hears")
    func addAppReadsUnknownAudioRecording() async {
        let (scratch, sut, app) = addAppPermissionsBench()
        // Allowed while monitoring hears sound, missing once it can't (Add
        // an App read it as allowed before, 2026-10-19).
        scratch.audio = nil
        #expect(await sut.checkPermissions(app, scriptable: false).audio == .allowed)
        sut.status.detection = .unavailable
        #expect(await sut.checkPermissions(app, scriptable: false).audio == .denied)
    }

    @MainActor
    @Test("Add an App reads Audio Recording in AntiDot mode too: its window goes by the mode")
    func addAppReadsAudioRecordingInAntiDot() async {
        let (scratch, sut, app) = addAppPermissionsBench()
        scratch.audio = .denied
        sut.settingsModel.useAntiDotMode()
        #expect(await sut.checkPermissions(app, scriptable: false).audio == .denied)
    }

    @MainActor
    @Test("Add an App's Allow… asks for Accessibility by macOS's prompt, then System Settings, and for Automation turned down, by System Settings")
    func addAppAsksAccessibilityAndAutomation() async {
        let (scratch, sut, app) = addAppPermissionsBench()
        scratch.running = [app.bundleID]
        let scripted = await sut.checkPermissions(app, scriptable: true)
        scratch.trusted = false
        await sut.requestCheckPermission(.accessibility, app: app, current: await sut.checkPermissions(app, scriptable: false))
        #expect(scratch.asked == ["prompt accessibility", "open Privacy_Accessibility"])
        await sut.requestCheckPermission(.automation, app: app, current: scripted)
        #expect(scratch.asked.last == "open Privacy_Automation")
    }

    @MainActor
    @Test("Add an App's Allow… for Audio Recording turned down opens System Settings; then AutoHush waits for a reopen, in Add an App and in the menu")
    func addAppAsksAudioRecording() async {
        let (scratch, sut, app) = addAppPermissionsBench()
        scratch.audio = .denied
        #expect(!sut.status.awaitsReopenForAudioRecording)
        await sut.requestCheckPermission(.audioRecording, app: app, current: await sut.checkPermissions(app, scriptable: false))
        #expect(scratch.asked.last == "open Privacy_AudioCapture")
        #expect(sut.status.awaitsReopenForAudioRecording)
        #expect(await sut.checkPermissions(app, scriptable: false).audio == .needsReopen)
    }

    @MainActor
    @Test("Add an App's Allow… for Audio Recording never asked shows macOS's own prompt")
    func addAppAsksAudioRecordingFirst() async {
        let (scratch, sut, app) = addAppPermissionsBench()
        scratch.audio = .notDetermined
        await sut.requestCheckPermission(.audioRecording, app: app, current: await sut.checkPermissions(app, scriptable: false))
        #expect(scratch.asked.last == "ask audio")
    }

    // MARK: - The window watch

    @MainActor
    @Test("while the welcome window shows with no player chosen, the players installed and the permissions are followed; closed while it asked for them, it's done")
    func watchFollowsWelcome() async {
        let scratch = Scratch()
        scratch.installed = [Players.first]
        scratch.audio = .denied
        let clock = ManualSleep()
        let (sut, _) = makeSUT(scratch, chosenPlayer: nil, windowWatchSleep: clock.sleep)
        sut.handleApplicationDidLaunch(bundleIdentifier: Players.first) // brings the welcome window
        await TestWait.until { clock.sleeping == 1 }
        #expect(sut.settingsModel.permissions.audio == .denied)

        scratch.installed.insert(Players.second) // installed meanwhile
        clock.step()
        await TestWait.until { sut.status.playerOptions.allSatisfy(\.isInstalled) }

        sut.chooseMusicPlayer(Players.second) // it goes on to the permissions
        #expect(sut.settingsModel.welcomeAsksPermissions)
        // A player is chosen: the folder watch follows the players, the window watch no longer.
        await TestWait.until { clock.sleeping == 1 }
        scratch.installed.remove(Players.first)
        clock.step()
        await TestWait.until { clock.sleeping == 1 }
        #expect(sut.status.playerOptions.first { $0.bundleID == Players.first }?.isInstalled == true)
        scratch.chooser.close() // closed instead of Done: the same
        clock.step()
        await TestWait.until { !sut.settingsModel.welcomeAsksPermissions }
    }

    @MainActor
    @Test("while Settings is open, the window watch follows what its page needs: launch at login, switched on in System Settings")
    func watchFollowsSettings() async {
        let scratch = Scratch()
        let clock = ManualSleep()
        let (sut, _) = makeSUT(scratch, windowWatchSleep: clock.sleep)
        sut.settingsWindowController = SettingsWindowController(model: sut.settingsModel)
        sut.settingsWindowController?.show(page: .general)
        defer { sut.settingsWindowController?.close() }
        sut.windowWatch.wake()
        await TestWait.until { clock.sleeping == 1 }
        #expect(!sut.settingsModel.launchAtLoginEnabled)
        scratch.launchAtLogin.isEnabled = true
        clock.step()
        await TestWait.until { sut.settingsModel.launchAtLoginEnabled }
    }

    @MainActor
    @Test("while only the learning window shows, the permissions are followed, not the players")
    func watchFollowsLearning() async {
        let scratch = Scratch()
        let webApp = scratch.offerWebApp(.learning(hasPlayed: false))
        let clock = ManualSleep()
        let (sut, _) = makeSUT(scratch, windowWatchSleep: clock.sleep)
        sut.chooseMusicPlayer(webApp.bundleID) // opens the learning window
        #expect(scratch.learningWindow.isOpen)
        await TestWait.until { clock.sleeping == 1 }

        scratch.audio = .denied
        scratch.installed.remove(Players.first)
        clock.step()
        await TestWait.until { sut.settingsModel.permissions.audio == .denied }
        #expect(sut.status.playerOptions.first { $0.bundleID == Players.first }?.isInstalled == true) // not looked at again
    }

    // MARK: - Permissions while running

    @MainActor
    @Test("reopening opens AutoHush again once it has quit, then quits; if that can't be set up, it stays open")
    func reopenRelaunchesThenQuits() {
        let (sut, _) = makeSUT()
        var calls: [String] = []
        sut.reopen(openAfterExit: { calls.append("open \($0.lastPathComponent)") }, terminate: { calls.append("quit") })
        #expect(calls == ["open \(Bundle.main.bundleURL.lastPathComponent)", "quit"])

        calls = []
        sut.reopen(openAfterExit: { _ in throw CocoaError(.fileNoSuchFile) }, terminate: { calls.append("quit") })
        #expect(calls.isEmpty)
    }
}
