import AppKit
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushPlayers
import SpotifySupport
import AutoHushTestSupport

@Suite("SettingsModel")
@MainActor
struct SettingsModelTests {
    private final class ActionLog {
        var calls: [String] = []
    }

    private func makeModel(_ controller: MockLaunchAtLoginController, _ log: ActionLog = ActionLog()) -> SettingsModel {
        SettingsModel(launchAtLoginController: controller, actions: .init(
            setAutoPause: { log.calls.append("autoPause \($0)") },
            setIgnored: { log.calls.append("ignore \($0.id) \($1)") },
            forgetApp: { log.calls.append("forget \($0.id)") },
            forgetAllApps: { log.calls.append("forgetAll") },
            setTimings: { log.calls.append("timings \($0.startConfirmation)") },
            setDetectionMethod: { log.calls.append("method \($0.rawValue)") },
            setChecksForUpdates: { log.calls.append("autoUpdate \($0)") },
            setInstallsUpdates: { log.calls.append("autoInstall \($0)") },
            checkForUpdates: { log.calls.append("checkNow") }
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

        model.setAutoPause(false)
        model.setPausesMusic(false, for: vlc)
        model.forget(vlc)
        model.forgetAllApps()
        model.setTimings(TimingSettings(startConfirmation: 99))
        model.setDetectionMethod(.openStreams)
        model.setChecksForUpdates(false)
        model.setInstallsUpdates(false)
        model.checkForUpdates()

        #expect(log.calls == [
            "autoPause false", "ignore org.videolan.vlc true", "forget org.videolan.vlc", "forgetAll",
            "timings 5.0", "method openStreams", "autoUpdate false", "autoInstall false", "checkNow",
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
}

@Suite("SettingsWindowController")
@MainActor
struct SettingsWindowControllerTests {
    @Test("has General, Apps and Advanced tabs in a toolbar")
    func tabs() throws {
        let model = SettingsModel(
            launchAtLoginController: MockLaunchAtLoginController(isEnabled: false),
            actions: .init(setAutoPause: { _ in }, setIgnored: { _, _ in }, forgetApp: { _ in }, forgetAllApps: {},
                           setTimings: { _ in }, setDetectionMethod: { _ in },
                           setChecksForUpdates: { _ in }, setInstallsUpdates: { _ in }, checkForUpdates: {})
        )
        let sut = SettingsWindowController(model: model)
        let tabController = try #require(sut.window?.contentViewController as? NSTabViewController)
        #expect(tabController.tabStyle == .toolbar)
        #expect(tabController.tabViewItems.map(\.label) == ["General", "Apps", "Advanced"])
        #expect(tabController.tabViewItems.allSatisfy { $0.image != nil })
    }
}
