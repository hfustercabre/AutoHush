import AppKit
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("Windows")
@MainActor
struct WindowTitleTests {
    private func makeModel() -> SettingsModel {
        SettingsModel(
            launchAtLoginController: MockLaunchAtLoginController(isEnabled: false),
            actions: .init(chooseMusicPlayer: { _ in }, setAutoPause: { _ in }, setIgnored: { _, _ in },
                           forgetApp: { _ in }, forgetAllApps: {},
                           setTimings: { _ in }, setDetectionMethod: { _ in },
                           setChecksForUpdates: { _ in }, setAutomaticUpdates: { _ in }, checkForUpdates: {},
                           openNotificationSettings: {})
        )
    }

    @Test("the welcome window's title is its page's, and follows it")
    func welcomeTitle() async {
        let model = makeModel()
        let sut = PlayerChooserWindowController(model: model, tallestPage: 600)
        #expect(sut.window?.title == "Choose Your Media Player")
        model.welcomeAsksPermissions = true
        await TestWait.until { sut.window?.title == "Allow AutoHush to Work" }
        #expect(sut.window?.title == "Allow AutoHush to Work")
        model.showWelcomePlayers()
        await TestWait.until { sut.window?.title == "Choose Your Media Player" }
        #expect(sut.window?.title == "Choose Your Media Player")
    }

    @Test("the learning window's title names the chosen player, and follows it")
    func learningTitle() async {
        let model = makeModel()
        model.playerOptions = [
            PlayerOption(bundleID: "com.apple.Safari.WebApp.A", name: "YT Music", appURL: URL(fileURLWithPath: "/Applications/A.app"),
                         kind: .safariWebApp),
            PlayerOption(bundleID: "com.apple.Safari.WebApp.B", name: "Deezer", appURL: URL(fileURLWithPath: "/Applications/B.app"),
                         kind: .safariWebApp),
        ]
        model.chosenPlayerID = "com.apple.Safari.WebApp.A"
        let sut = LearningWindowController(model: model)
        #expect(sut.window?.title == "Learn YT Music’s Controls")
        model.chosenPlayerID = "com.apple.Safari.WebApp.B"
        await TestWait.until { sut.window?.title == "Learn Deezer’s Controls" }
        #expect(sut.window?.title == "Learn Deezer’s Controls")
    }

    @Test("AutoHush stays in the Dock for its own windows only: titled ones, not panels or borderless ones")
    func dockCountsAppWindows() {
        let titled = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        let borderless = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        #expect(DockPresence.isAppWindow(titled))
        #expect(!DockPresence.isAppWindow(panel)) // alerts, file panels
        #expect(!DockPresence.isAppWindow(borderless)) // the menu's
    }

    @Test("Return in the welcome window's search picks the one player it narrowed down to, if it can be picked")
    func returnPicksOnlyMatch() {
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        let options = [
            PlayerOption(bundleID: "com.example.spotify", name: "Spotify", appURL: url),
            PlayerOption(bundleID: "com.example.music", name: "Music", appURL: url),
            PlayerOption(bundleID: "com.example.vlc", name: "VLC", appURL: nil), // not installed
        ]
        #expect(PlayerChooserView.onlyMatch(of: options, search: "spo")?.bundleID == "com.example.spotify")
        #expect(PlayerChooserView.onlyMatch(of: options, search: "i") == nil) // Spotify and Music
        #expect(PlayerChooserView.onlyMatch(of: options, search: "vlc") == nil) // can't be picked
        #expect(PlayerChooserView.onlyMatch(of: options, search: "xyz") == nil)
        #expect(PlayerChooserView.onlyMatch(of: options, search: "") == nil) // nothing typed: Return is Continue
        #expect(PlayerChooserView.onlyMatch(of: options, search: "  ") == nil)
    }

    @Test("a window shown stays open while macOS counts it as not visible (AutoHush hidden with ⌘H), until it closes")
    func shownIsOpenUntilClosed() async {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled, .closable],
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        #expect(!window.isOpen)
        window.showInFront()
        window.orderOut(nil) // as AutoHush hidden leaves it: not visible
        #expect(!window.isVisible && window.isOpen)
        window.close()
        await TestWait.until { !window.isOpen }
        #expect(!window.isOpen)
    }
}
