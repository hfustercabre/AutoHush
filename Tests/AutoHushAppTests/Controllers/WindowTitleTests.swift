import AppKit
import SwiftUI
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport
@testable import CheckPanel
import PlayerCheckKit

/// The logs window and Settings keep their place under a name of their
/// own, which AppKit gives one window at a time: tests run at once, each
/// with its own, removed after.
@Suite("Windows", .waitsTimeLimit)
@MainActor
final class WindowTitleTests {
    private let actions = FakeAppActions()
    private let updates = FakeUpdateCommands()
    private let frameName = "WindowTitleTests-\(UUID().uuidString)"

    deinit {
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(frameName)")
    }

    private func makeLogs(_ source: LogsModelTests.FakeLog = LogsModelTests.FakeLog()) -> LogsWindowController {
        LogsWindowController(model: LogsModel(source: source), frameName: frameName)
    }

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

    /// Settings and the logs window take the name their place is kept
    /// under, which a second window can't have: their tests give each one a
    /// name of its own (SettingsWindowControllerTests, logsWindow).
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

    @Test("a window's content starts below its title bar, not under it: there, on macOS 14 and 15, its layout looped as it resized")
    func contentBelowTitleBar() throws {
        for sut in centeredWindows().windows {
            let window = try #require(sut.window)
            #expect(!window.styleMask.contains(.fullSizeContentView))
            #expect(window.contentView?.frame.height == window.contentLayoutRect.height)
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

    @Test("a floating window keeps its top edge only while it's open: closed, its watch ends, and shown again, it starts again")
    func floatingWatchEndsAtClose() async throws {
        let floating = AddWebAppWindowController(model: AddWebAppModel(), settings: makeModel())
        let screen = try #require(NSScreen.screens.last)
        floating.cornerScreen = { screen }
        floating.show()
        #expect(!floating.edgeObservers.isEmpty)
        floating.close()
        await TestWait.until { !floating.isOpen && floating.edgeObservers.isEmpty }
        #expect(floating.edgeObservers.isEmpty) // each Learn Again's new window left the old one's behind
        floating.show()
        defer { floating.close() }
        #expect(!floating.edgeObservers.isEmpty)
    }

    @Test("the logs window keeps its place and size under its name")
    func logsWindow() {
        let logs = makeLogs()
        // Its place and size kept between launches: the controller gives its
        // window its name (on macOS 14 and 15 it would clear one set before).
        #expect(logs.windowFrameAutosaveName == frameName)
        #expect(logs.window?.frameAutosaveName == frameName)
        #expect(LogsWindowController.frameName == "Logs Window")
    }

    @Test("the logs window, never opened before, opens centered, at least its smallest size")
    func logsWindowCentered() throws {
        let logs = makeLogs() // never opened before: its name is new
        defer { logs.close() }
        logs.show()
        let logsArea = try #require(logs.window?.screen?.visibleFrame)
        #expect(abs((logs.window?.frame.midX ?? 0) - logsArea.midX) <= 1)
        let size = try #require(logs.window.map { $0.contentRect(forFrameRect: $0.frame).size })
        #expect(size.width >= LogsWindowController.minimumSize.width && size.height >= LogsWindowController.minimumSize.height)
    }

    @Test("the logs window can be resized, but never goes full screen")
    func logsWindowResizable() {
        let logs = makeLogs()
        #expect(logs.window?.styleMask.contains(.resizable) == true)
        #expect(logs.window?.collectionBehavior.contains(.fullScreenNone) == true) // never full screen
    }

    @Test("the logs window shown again while open keeps its search")
    func logsWindowKeepsSearch() {
        let log = LogsModelTests.FakeLog()
        let logs = makeLogs(log)
        defer { logs.close() }
        logs.show()
        logs.model.search = "fade"
        logs.show() // shown again while open: the search stays
        #expect(logs.model.search == "fade" && log.handlers.count == 1)
    }

    @Test("the logs window follows new lines while it's open, and no longer once closed")
    func logsWindowFollowsLines() async {
        let log = LogsModelTests.FakeLog()
        let logs = makeLogs(log)
        logs.show()
        #expect(logs.window?.isOpen == true && log.handlers.count == 1) // new lines follow
        logs.close()
        await TestWait.until { logs.window?.isOpen != true }
        #expect(log.handlers.isEmpty)
    }

    /// Each test reads its panel and shades from its own controller, not
    /// from the process's windows: other suites in the same test process
    /// (AddAppFeature's) show check panels and shades of their own meanwhile
    /// (B2, the full check, 2026-10-27: a test took another's panel as its
    /// own).
    @MainActor
    @Suite("The check's panel", .serialized)
    struct CheckPanelWindows {
        /// `NSApp` is set up here when this suite runs alone (B3, the full
        /// check, 2026-10-27: it crashed, nil, with no other suite before it).
        init() {
            _ = NSApplication.shared
        }

        /// A check running on the stand-ins, its panel shown.
        private func panelShown() async throws -> (world: World, model: AddAppModel, sut: CheckPanelController, panel: NSPanel) {
            let world = World()
            let model = await AddAppModel.ready(on: world)
            model.startCheck()
            await TestWait.until { world.report != nil }
            let sut = CheckPanelController()
            sut.show(world.apps[0], model: model)
            let panel = try #require(sut.panel)
            return (world, model, sut, panel)
        }

        /// Ends the check and waits until the model has taken its end: its
        /// task holds the model, and the model the world, until then (B6, the
        /// full check, 2026-10-20: a world freed only after the test process
        /// ended left its folder behind).
        private func endCheck(_ world: World, _ model: AddAppModel) async {
            world.run.finish(.stopped)
            await TestWait.until { model.stage != .checking }
        }

        @Test("the check's panel is on every desktop, in the screen's corner, and never takes the keyboard")
        func checkPanel() async throws {
            let (world, model, sut, panel) = try await panelShown()
            #expect(panel.isVisible && panel.styleMask.contains(.nonactivatingPanel) && !panel.canBecomeKey)
            #expect(panel.collectionBehavior.contains(.canJoinAllSpaces) && panel.level == .floating)
            let corner = NSScreen.screens.first?.visibleFrame ?? .zero // the main display's, above the Dock
            #expect(abs(panel.frame.maxX - (corner.maxX - 16)) <= 1 && abs(panel.frame.minY - (corner.minY + 16)) <= 1)
            sut.hide()
            await endCheck(world, model)
        }

        @Test("only while the check blocks input does a shade under its panel dim each screen")
        func checkPanelShades() async throws {
            let (world, model, sut, panel) = try await panelShown()
            #expect(sut.shades.isEmpty)
            world.report?(CheckReportLine.blocked)
            await TestWait.until { panel.level == CheckPanelController.panelLevel && sut.shades.count == NSScreen.screens.count }
            let shades = sut.shades
            #expect(shades.allSatisfy { shade in shade.isVisible && NSScreen.screens.contains { $0.frame == shade.frame } })
            #expect(shades.allSatisfy { $0.ignoresMouseEvents && $0.collectionBehavior.contains(.canJoinAllSpaces) && $0.level.rawValue < panel.level.rawValue })
            world.report?(CheckReportLine.free)
            // They fade out, then go.
            await TestWait.until { panel.level == .floating && sut.shades.isEmpty && !shades.contains(where: \.isVisible) }
            sut.hide()
            await endCheck(world, model)
        }

        @Test("the check's panel hidden, it and its shades all go")
        func checkPanelHidden() async throws {
            let (world, model, sut, panel) = try await panelShown()
            world.report?(CheckReportLine.blocked)
            await TestWait.until { !sut.shades.isEmpty }
            let shades = sut.shades
            sut.hide()
            #expect(!panel.isVisible && !shades.contains(where: \.isVisible) && sut.panel == nil && sut.shades.isEmpty)
            await endCheck(world, model)
        }
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
