import AppKit
import SwiftUI
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport
@testable import CheckPanel
import CheckedPlayers

@Suite("Windows")
@MainActor
struct WindowTitleTests {
    private let actions = FakeAppActions()
    private let updates = FakeUpdateCommands()

    private func makeModel() -> SettingsModel { .forTests(actions: actions, updates: updates) }

    @Test("the welcome window's title is its page's, and follows it")
    func welcomeTitle() async {
        let model = makeModel()
        let sut = PlayerChooserWindowController(model: model, tallestPage: 600)
        #expect(sut.window?.title == "Choose Your Media Player")
        model.welcomeAsksPermissions = true
        await TestWait.until { sut.window?.title == "Allow AutoHush to Work" }
        model.showWelcomePlayers()
        await TestWait.until { sut.window?.title == "Choose Your Media Player" }
    }

    @Test("the learning window's title names the chosen player, and follows it; closed (Later, or its close button), it says so")
    func learningTitle() async {
        let model = makeModel()
        model.state.status.playerOptions = [
            PlayerOption(bundleID: "com.apple.Safari.WebApp.A", name: "YT Music", appURL: URL(fileURLWithPath: "/Applications/A.app"),
                         kind: .safariWebApp),
            PlayerOption(bundleID: "com.apple.Safari.WebApp.B", name: "Deezer", appURL: URL(fileURLWithPath: "/Applications/B.app"),
                         kind: .safariWebApp),
        ]
        model.state.status.chosenPlayerID = "com.apple.Safari.WebApp.A"
        let sut = LearningWindowController(model: model)
        #expect(sut.window?.title == "Learn YT Music’s Controls")
        model.state.status.chosenPlayerID = "com.apple.Safari.WebApp.B"
        await TestWait.until { sut.window?.title == "Learn Deezer’s Controls" }

        let closes = CallLog()
        sut.onClose = { closes.calls.append("closed") } // AppDelegate keeps what was learned then
        sut.show()
        sut.close()
        #expect(closes.calls == ["closed"])
    }

    /// Settings and the logs window are checked where they're made one at a
    /// time (SettingsWindowControllerTests.limits, logsWindow): each takes
    /// the name its place is kept under, which a second can't have.
    @Test("no AutoHush window can go full screen: welcome and Add an App's none; Add a Web App and learning only over another app's")
    func noFullScreen() {
        let model = makeModel()
        let world = World()
        let addApp = AddAppModel(world)
        let windows: [NSWindow?] = [
            PlayerChooserWindowController(model: model, tallestPage: 600).window,
            AddAppWindowController(model: addApp).window,
            AppChooserWindowController(model: addApp).window,
            CheckWarningWindowController(app: world.apps[0], muting: .none) {}.window,
            AddWebAppWindowController(model: AddWebAppModel(), settings: model).window,
            LearningWindowController(model: model).window,
        ]
        for window in windows {
            let behavior = window?.collectionBehavior ?? []
            #expect(!behavior.contains(.fullScreenPrimary))
            #expect(behavior.contains(.fullScreenNone) || behavior.contains(.fullScreenAuxiliary))
        }
        #expect(windows.prefix(4).allSatisfy { $0?.collectionBehavior.contains(.fullScreenNone) == true })
        #expect(windows.suffix(2).allSatisfy { $0?.collectionBehavior.contains(.fullScreenAuxiliary) == true })
    }

    /// The windows that open centered: Add an App's, its list of apps, and
    /// the warning before its check.
    private func centeredWindows() -> (world: World, windows: [HostedWindowController]) {
        let world = World()
        let addApp = AddAppModel(world)
        return (world, [
            AddAppWindowController(model: addApp),
            AppChooserWindowController(model: addApp),
            CheckWarningWindowController(app: world.apps[0], muting: .none) {},
        ])
    }

    @Test("a window opens centered, under a title bar of the usual height")
    func opensCentered() throws {
        for sut in centeredWindows().windows {
            let window = try #require(sut.window)
            sut.show()
            let area = try #require(window.screen?.visibleFrame)
            #expect(sut.isOpen && abs(window.frame.midX - area.midX) <= 1)
            #expect(window.frame.height - window.contentLayoutRect.height == HostedWindowController.titleBarHeight)
            sut.close()
        }
    }

    @Test("a window shown again stays where the user moved it")
    func shownAgainStaysPut() throws {
        for sut in centeredWindows().windows {
            let window = try #require(sut.window)
            sut.show()
            let area = try #require(window.screen?.visibleFrame)
            let moved = NSPoint(x: area.minX + 10, y: area.minY + 10) // by the user
            window.setFrameOrigin(moved)
            sut.show()
            #expect(window.frame.origin == moved)
            sut.close()
        }
    }

    @Test("brought forward as the menu opens, a window comes in front if it's open; a closed one stays closed")
    func broughtForwardIfOpen() async throws {
        for sut in centeredWindows().windows {
            let window = try #require(sut.window)
            sut.show()
            // Another app's window over it, as the menu opens.
            let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            other.isReleasedWhenClosed = false
            other.orderFrontRegardless()
            sut.bringForward()
            let order = NSApp.orderedWindows
            #expect((order.firstIndex(of: window) ?? .max) < (order.firstIndex(of: other) ?? .max))
            other.close()
            sut.close()
            await TestWait.until { !sut.isOpen }
            sut.bringForward() // as when the menu opens: a closed window stays closed
            #expect(!sut.isOpen)
        }
    }

    @Test("Add an App's window closed, what it opened closes too")
    func addAppClosesWhatItOpened() async throws {
        let (world, windows) = centeredWindows()
        let sut = try #require(windows.first)
        sut.show()
        sut.close()
        await TestWait.until { !sut.isOpen }
        #expect(world.warningsClosed == 1)
    }

    @Test("the check's warning closes before its Start starts the check (which counts the windows over the app); its Cancel closes it")
    func warningClosesBeforeStart() async throws {
        let world = World()
        let started = CallLog()
        var warningWindow: NSWindow?
        let warning = CheckWarningWindowController(app: world.apps[0], muting: .none) {
            started.calls.append(warningWindow?.isVisible == false ? "started, closed" : "started, open")
        }
        warningWindow = warning.window
        let warningView = try #require(warning.window?.contentViewController as? NSHostingController<CheckWarningView>)
        warning.show()
        warningView.rootView.start()
        #expect(started.calls == ["started, closed"])
        await TestWait.until { !warning.isOpen }
        warning.show()
        warningView.rootView.cancel()
        await TestWait.until { !warning.isOpen }
        #expect(!warning.isOpen && started.calls.count == 1)
    }

    @Test("Add a Web App's window floats in the top-right corner, its top edge kept as it grows")
    func floatsInTheCorner() async throws {
        let floating = AddWebAppWindowController(model: AddWebAppModel(), settings: makeModel())
        let window = try #require(floating.window)
        let screen = try #require(NSScreen.screens.last) // as if the pointer were on it
        floating.cornerScreen = { screen }
        floating.show()
        defer { floating.close() }
        let area = screen.visibleFrame
        let margin = HostedWindowController.cornerMargin
        #expect(window.level == .floating)
        #expect(abs(window.frame.maxX - (area.maxX - margin)) <= 1 && abs(window.frame.maxY - (area.maxY - margin)) <= 1)
        for top in [window.frame.maxY, window.frame.maxY - 50] {
            window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top)) // the second time, moved by the user
            let height = window.frame.height + 40 // grown from its bottom edge, as its content grows it
            window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: window.frame.width, height: height)), display: false)
            await TestWait.until { window.frame.maxY == top }
            #expect(window.frame.maxY == top && window.frame.height == height)
        }
    }

    @Test("the logs window keeps its place and size under its name, opens centered, resizable but never full screen; shown again, its search stays; closed, it no longer follows new lines")
    func logsWindow() async throws {
        let log = LogsModelTests.FakeLog()
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(LogsWindowController.frameName)") // never opened before
        let logs = LogsWindowController(model: LogsModel(source: log))
        // Its place and size kept between launches: the controller gives its
        // window its name (on macOS 14 and 15 it would clear one set before).
        #expect(logs.windowFrameAutosaveName == LogsWindowController.frameName)
        #expect(logs.window?.frameAutosaveName == LogsWindowController.frameName)
        logs.show()
        #expect(logs.window?.isOpen == true && log.handlers.count == 1) // new lines follow
        let logsArea = try #require(logs.window?.screen?.visibleFrame)
        #expect(abs((logs.window?.frame.midX ?? 0) - logsArea.midX) <= 1)
        let size = try #require(logs.window.map { $0.contentRect(forFrameRect: $0.frame).size })
        #expect(size.width >= LogsWindowController.minimumSize.width && size.height >= LogsWindowController.minimumSize.height)
        #expect(logs.window?.styleMask.contains(.resizable) == true)
        #expect(logs.window?.collectionBehavior.contains(.fullScreenNone) == true) // never full screen
        logs.model.search = "fade"
        logs.show() // shown again while open: the search stays
        #expect(logs.model.search == "fade" && log.handlers.count == 1)
        logs.close()
        await TestWait.until { logs.window?.isOpen != true }
        #expect(log.handlers.isEmpty)
    }

    @Test("the check's panel is on every desktop and never takes the keyboard; while the check blocks input, a shade under it dims each screen; hidden, they all go")
    func checkPanel() async throws {
        let world = World()
        world.playing = true
        let model = AddAppModel(world)
        model.reset()
        await model.loadApps()
        model.continueWithApp()
        await TestWait.until { model.stage == .ready }
        model.startCheck()
        await TestWait.until { world.report != nil }
        let sut = CheckPanelController()
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        sut.show(world.apps[0], model: model)
        let panel = try #require(NSApp.windows.first { !before.contains(ObjectIdentifier($0)) } as? NSPanel)
        let shades = { NSApp.windows.filter { $0.level == CheckPanelController.shadeLevel && $0.isVisible } }
        #expect(panel.isVisible && panel.styleMask.contains(.nonactivatingPanel) && !panel.canBecomeKey)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces) && panel.level == .floating)
        let corner = NSScreen.screens.first?.visibleFrame ?? .zero // the main display's, above the Dock
        #expect(abs(panel.frame.maxX - (corner.maxX - 16)) <= 1 && abs(panel.frame.minY - (corner.minY + 16)) <= 1)
        #expect(shades().isEmpty)

        world.report?(CheckReportLine.blocked)
        await TestWait.until { panel.level == CheckPanelController.panelLevel && shades().count == NSScreen.screens.count }
        #expect(shades().allSatisfy { shade in NSScreen.screens.contains { $0.frame == shade.frame } })
        #expect(shades().allSatisfy { $0.ignoresMouseEvents && $0.collectionBehavior.contains(.canJoinAllSpaces) && $0.level.rawValue < panel.level.rawValue })
        world.report?(CheckReportLine.free)
        await TestWait.until { panel.level == .floating && shades().isEmpty }

        world.report?(CheckReportLine.blocked)
        await TestWait.until { !shades().isEmpty }
        sut.hide()
        #expect(!panel.isVisible && shades().isEmpty)
        world.run.finish(.stopped)
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

    @Test("tiles that share a name count as one for Return: the app first, then an added web app, then a suggested one")
    func returnPicksAmongSameName() {
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        let app = PlayerOption(bundleID: "com.example.spotify", name: "Spotify", appURL: url)
        var suggested = PlayerOption(bundleID: "com.example.webapp.spotify", name: "Spotify", appURL: nil)
        suggested.kind = .safariWebApp
        suggested.webAddress = "open.spotify.com"
        #expect(PlayerChooserView.onlyMatch(of: [app, suggested], search: "spo")?.bundleID == app.bundleID)

        // Without the app, the suggestion is the one that can be picked.
        let missing = PlayerOption(bundleID: app.bundleID, name: "Spotify", appURL: nil)
        #expect(PlayerChooserView.onlyMatch(of: [missing, suggested], search: "spotify")?.bundleID == suggested.bundleID)

        // An app and an added web app of the same name: the app.
        let music = PlayerOption(bundleID: "com.example.music", name: "Apple Music", appURL: url)
        var added = PlayerOption(bundleID: "com.example.webapp.music", name: "Apple Music", appURL: url)
        added.kind = .safariWebApp
        #expect(PlayerChooserView.onlyMatch(of: [added, music], search: "apple music")?.bundleID == music.bundleID)

        // Different names still need a closer search.
        var ytMusic = PlayerOption(bundleID: "com.example.webapp.yt", name: "YT Music", appURL: url)
        ytMusic.kind = .safariWebApp
        #expect(PlayerChooserView.onlyMatch(of: [music, ytMusic], search: "music") == nil)
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
    }

    @Test("a closed window brought forward follows the user to the desktop they're on for a moment, then stays where it opened")
    func closedWindowComesToTheActiveDesktop() async {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled, .closable],
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil) }
        #expect(!window.isVisible && !window.collectionBehavior.contains(.moveToActiveSpace))
        window.bringForward(following: 0) // a second in the app
        #expect(window.collectionBehavior.contains(.moveToActiveSpace))
        await TestWait.until { !window.collectionBehavior.contains(.moveToActiveSpace) }
    }
}
