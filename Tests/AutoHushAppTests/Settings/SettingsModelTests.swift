import AppKit
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("SettingsModel")
@MainActor
struct SettingsModelTests {
    private final class ActionLog {
        var calls: [String] = []
    }

    private func makeModel(_ controller: MockLaunchAtLoginController, _ log: ActionLog = ActionLog()) -> SettingsModel {
        SettingsModel(launchAtLoginController: controller, actions: .init(
            chooseMusicPlayer: { log.calls.append("player \($0)") },
            setAutoPause: { log.calls.append("autoPause \($0)") },
            setIgnored: { log.calls.append("ignore \($0.id) \($1)") },
            forgetApp: { log.calls.append("forget \($0.id)") },
            forgetAllApps: { log.calls.append("forgetAll") },
            setTimings: { log.calls.append("timings \($0.startConfirmation)") },
            setDetectionMethod: { log.calls.append("method \($0.rawValue)") },
            setChecksForUpdates: { log.calls.append("autoUpdate \($0)") },
            setAutomaticUpdates: { log.calls.append("updates \($0.rawValue)") },
            checkForUpdates: { log.calls.append("checkNow") },
            openNotificationSettings: { log.calls.append("notificationSettings") }
        ))
    }

    @Test("reflects the login item's state")
    func reflectsLaunchAtLogin() {
        #expect(makeModel(MockLaunchAtLoginController(isEnabled: true)).launchAtLoginEnabled)
        #expect(!makeModel(MockLaunchAtLoginController(isEnabled: false)).launchAtLoginEnabled)
    }

    @Test("turning launch at login on registers the login item")
    func enableLaunchAtLogin() {
        let controller = MockLaunchAtLoginController(isEnabled: false)
        let model = makeModel(controller)
        model.setLaunchAtLogin(true)
        #expect(controller.setEnabledCalls == [true])
        #expect(model.launchAtLoginEnabled)
        #expect(model.launchAtLoginError == nil)
    }

    @Test("a failed change keeps the real state and shows the error inline")
    func failedLaunchAtLogin() {
        let controller = MockLaunchAtLoginController(isEnabled: false)
        controller.setEnabledResult = .failure(StubError.failed)
        let model = makeModel(controller)
        model.setLaunchAtLogin(true)
        #expect(!model.launchAtLoginEnabled)
        #expect(model.launchAtLoginError == "Could not change the login item: stub failed")

        controller.setEnabledResult = .success(())
        model.setLaunchAtLogin(true)
        #expect(model.launchAtLoginError == nil)
    }

    @Test("opening Login Items settings is delegated")
    func openLoginItems() {
        let controller = MockLaunchAtLoginController(isEnabled: false)
        makeModel(controller).openLoginItemsSettings()
        #expect(controller.openSystemSettingsCallCount == 1)
    }

    @Test("the apps list merges seen and ignored apps, sorted by name")
    func appsList() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC", bundlePath: "/Applications/VLC.app")
        let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome")
        let zoom = AudioSource(id: "us.zoom.xos", name: "zoom.us")
        model.setApps(seen: [vlc, chrome], ignored: [AudioSource(id: vlc.id, name: "VLC"), zoom])

        #expect(model.apps.map(\.source.name) == ["Google Chrome", "VLC", "zoom.us"])
        #expect(model.apps.map(\.isIgnored) == [false, true, true])
        #expect(model.apps[1].source.bundlePath == "/Applications/VLC.app") // the seen entry keeps its icon
    }

    @Test("actions are forwarded; timings are clamped first")
    func forwardsActions() {
        let log = ActionLog()
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false), log)
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC")

        model.chooseMusicPlayer("com.example.player")
        model.setAutoPause(false)
        model.setPausesMusic(false, for: vlc)
        model.forget(vlc)
        model.forgetAllApps()
        model.setTimings(TimingSettings(startConfirmation: 99))
        model.setDetectionMethod(.openStreams)
        model.setChecksForUpdates(false)
        model.setAutomaticUpdates(.download)
        model.checkForUpdates()
        model.openNotificationSettings()

        #expect(log.calls == [
            "player com.example.player", "autoPause false", "ignore org.videolan.vlc true", "forget org.videolan.vlc", "forgetAll",
            "timings 5.0", "method openStreams", "autoUpdate false", "updates download", "checkNow",
            "notificationSettings",
        ])
        #expect(model.timings.startConfirmation == 5)
        #expect(model.detectionMethod == .openStreams)
    }

    @Test("AntiDot mode switches between audio levels and playback signals")
    func antiDotMode() {
        let log = ActionLog()
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false), log)
        #expect(!model.isAntiDotMode)

        model.setAntiDotMode(true)
        #expect(model.isAntiDotMode && model.detectionMethod == .playbackSignals)
        model.setDetectionMethod(.openStreams)
        model.setAntiDotMode(true) // already on: keeps the chosen method
        #expect(model.detectionMethod == .openStreams)
        model.setAntiDotMode(false)
        #expect(!model.isAntiDotMode && model.detectionMethod == .audioLevels)
        #expect(log.calls == ["method askApps", "method openStreams", "method audioLevels"])
    }

    @Test("restoring defaults applies the default timings")
    func restoreDefaults() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        model.setTimings(TimingSettings(stopGrace: 7))
        model.restoreDefaultTimings()
        #expect(model.timings == .defaults)
    }

    // MARK: - Notifications

    @Test("choices that notify are unavailable while notifications are off")
    func notifyingChoices() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        #expect(AutomaticUpdates.allCases.allSatisfy(model.isAvailable))
        model.notificationsOff = true
        #expect(!model.isAvailable(.notify))
        #expect(!model.isAvailable(.download))
        #expect(model.isAvailable(.install))
    }

    @Test("beside Check Now: the version until a check, then what it found; under it, when the last one was")
    func updateRow() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        #expect(model.updateTitle == "AutoHush")
        model.currentVersion = "0.3.11"
        #expect(model.updateTitle == "AutoHush 0.3.11")
        #expect(model.lastCheckedNote() == nil)

        let now = Date()
        model.lastUpdateCheck = now.addingTimeInterval(-2 * 3600)
        model.updateStatus = "AutoHush 0.3.11 is up to date."
        #expect(model.updateTitle == "AutoHush 0.3.11 is up to date.")
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        let when = formatter.localizedString(for: now.addingTimeInterval(-2 * 3600), relativeTo: now)
        #expect(model.lastCheckedNote(now: now) == "Last checked \(when)")
    }

    @Test("the notifications note blinks for a while, longer when asked again")
    func noteBlinks() async throws {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        model.noteFlashDuration = .milliseconds(600)
        model.noteFlashInterval = .milliseconds(20)

        model.flashNotificationsNote()
        #expect(model.notificationsNoteIsLit) // lit at once
        try await Task.sleep(for: .milliseconds(300))
        model.flashNotificationsNote() // from now, another 600 ms

        // Past the first 600 ms (with room for a busy test run), it still blinks.
        try await Task.sleep(for: .milliseconds(400))
        let before = model.notificationsNoteIsLit
        var toggled = false
        for _ in 0..<20 where !toggled {
            try await Task.sleep(for: .milliseconds(10))
            toggled = model.notificationsNoteIsLit != before
        }
        #expect(toggled)

        try await Task.sleep(for: .milliseconds(800))
        #expect(!model.notificationsNoteIsLit)
    }

}

@Suite("SettingsWindowController")
@MainActor
struct SettingsWindowControllerTests {
    @Test("has General, Apps and Advanced tabs in a toolbar")
    func tabs() throws {
        let model = SettingsModel(
            launchAtLoginController: MockLaunchAtLoginController(isEnabled: false),
            actions: .init(chooseMusicPlayer: { _ in }, setAutoPause: { _ in }, setIgnored: { _, _ in },
                           forgetApp: { _ in }, forgetAllApps: {},
                           setTimings: { _ in }, setDetectionMethod: { _ in },
                           setChecksForUpdates: { _ in }, setAutomaticUpdates: { _ in }, checkForUpdates: {},
                           openNotificationSettings: {})
        )
        let sut = SettingsWindowController(model: model)
        let tabController = try #require(sut.window?.contentViewController as? NSTabViewController)
        #expect(tabController.tabStyle == .toolbar)
        #expect(tabController.tabViewItems.map(\.label) == ["General", "Apps", "Advanced"])
        #expect(tabController.tabViewItems.allSatisfy { $0.image != nil })
    }

    @Test("when the shown tab's content changes height, the window follows at once and keeps its top")
    func fitsShownTab() async throws {
        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar
        let content = NSViewController()
        content.view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
        content.preferredContentSize = NSSize(width: 480, height: 300)
        tabs.addTabViewItem(NSTabViewItem(viewController: content))
        let window = NSWindow(contentViewController: tabs)
        window.setFrameOrigin(NSPoint(x: 100, y: 300))
        let top = window.frame.maxY
        let chrome = window.frame.height - (window.contentView?.frame.height ?? 0)

        content.preferredContentSize = NSSize(width: 480, height: 200)
        tabs.contentHeightDidChange()
        try await Task.sleep(for: .milliseconds(50))
        #expect(window.frame.height == 200 + chrome)
        #expect(window.frame.maxY == top)

        content.preferredContentSize = NSSize(width: 480, height: 360)
        tabs.contentHeightDidChange()
        try await Task.sleep(for: .milliseconds(50))
        #expect(window.frame.height == 360 + chrome)
        #expect(window.frame.maxY == top)
        window.close()
    }
}
