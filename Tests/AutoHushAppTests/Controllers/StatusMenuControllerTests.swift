import AppKit
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

/// One test at a time: each has its own notification centers (another
/// desktop, another window becoming key), but they share the menu bar.
@Suite("StatusMenuController", .serialized)
@MainActor
struct StatusMenuControllerTests {
    private let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome")
    private let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC")
    /// What the menu asked of AppDelegate and the updates, in order; the
    /// user's settings and the player session show their own changes.
    private let log = CallLog()
    private let actions: FakeAppActions
    private let updates: FakeUpdateCommands
    private let settings = UserSettings.inMemory()
    private let session = PlayerSession.noPlayer()

    init() {
        actions = FakeAppActions(log: log)
        updates = FakeUpdateCommands(log: log)
    }

    /// The menu's own notification centers: no other test's windows or
    /// desktops reach it, and its notifications reach no other menu.
    private let center = NotificationCenter()
    private let workspaceCenter = NotificationCenter()

    /// A menu whose timing waits only a turn (the tests await its tasks),
    /// with Reduce Motion off.
    private func makeController(settingsModel: SettingsModel? = nil) -> StatusMenuController {
        let sut = StatusMenuController(settings: settings, session: session, updates: updates, actions: actions, settingsModel: settingsModel)
        sut.notificationCenter = center
        sut.workspaceCenter = workspaceCenter
        sut.reducesMotion = { false }
        sut.pause = { _ in await Task.yield() }
        return sut
    }

    /// Ready to control the Jukebox player, paused for another app.
    private func readyStatus() -> AppStatus {
        var status = AppStatus()
        status.choosePlayer(named: "Jukebox")
        status.setHealth(.ready)
        status.playback = .pausedByMonitor
        return status
    }

    /// The menu opens anew, put together for the status (its panel not shown).
    private func reopen(_ sut: StatusMenuController) {
        sut.close()
        sut.open(showsPanel: false)
    }

    /// The menu's parts, in order: a warning by its row's title.
    private func parts(_ sut: StatusMenuController) -> [String] {
        sut.model.sections.map { section in
            switch section {
            case .card: "card"
            case .mediaPlayer: "mediaPlayer"
            case .warning(let permission): permission.grantTitle
            case .reopenAutoHush: PermissionText.reopen
            case .useAntiDot: PermissionText.useAntiDot
            case .snooze: "snooze"
            case .playingNow: "playingNow"
            case .recentlyPlayed: "recentlyPlayed"
            case .ignoredApps: "ignoredApps"
            case .settings: "settings"
            case .update: "update"
            case .toolbar: "toolbar"
            }
        }
    }

    /// The unfolded players, by their groups: "[Supported]", "[Other]",
    /// "[Web]" over their names, and a note when the search matched none.
    private func playerRows(_ sut: StatusMenuController) -> [String] {
        let list = sut.model.players
        var rows: [String] = list.showsSearch ? ["search"] : []
        if let note = list.noMatchNote { rows.append(note) }
        if !list.supportedApps.isEmpty { rows += ["[Supported]"] + list.supportedApps.map(\.option.name) }
        if list.showsOtherApps { rows += ["[Other]"] + list.otherApps.map(\.option.name) }
        if !list.webApps.isEmpty { rows += ["[Web]"] + list.webApps.map(\.option.name) }
        return rows
    }

    private func row(_ name: String, in sut: StatusMenuController) throws -> MenuPlayerList.Row {
        let list = sut.model.players
        return try #require((list.supportedApps + list.otherApps + list.webApps).first { $0.option.name == name }, "no player \"\(name)\"")
    }

    /// Waits until `log` has `count` calls: some commands run once the menu
    /// has closed.
    private func wait(for count: Int, in log: CallLog, sourceLocation: SourceLocation = #_sourceLocation) async {
        await TestWait.until(sourceLocation: sourceLocation) { log.calls.count >= count }
    }

    // MARK: - Layout

    @Test("the menu is the card, the duration buttons, Ignored Apps and the toolbar; playing apps and the settings add their parts")
    func layout() {
        let sut = makeController()
        defer { sut.remove() }
        sut.status = readyStatus()
        reopen(sut)
        #expect(parts(sut) == ["card", "mediaPlayer", "snooze", "ignoredApps", "toolbar"])

        var status = readyStatus()
        status.ignoredApps = [vlc]
        status.setActiveSources([vlc, chrome])
        sut.status = status
        reopen(sut)
        #expect(parts(sut) == ["card", "mediaPlayer", "snooze", "playingNow", "ignoredApps", "toolbar"])
        #expect(sut.model.listedSources == [chrome, vlc])

        let withSettings = makeController(settingsModel: SettingsModel(settings: settings, updates: updates, actions: actions,
                                                                        launchAtLoginController: MockLaunchAtLoginController(isEnabled: false)))
        defer { withSettings.remove() }
        withSettings.status = readyStatus()
        reopen(withSettings)
        #expect(parts(withSettings) == ["card", "mediaPlayer", "snooze", "ignoredApps", "settings", "toolbar"])
    }

    @Test("Recently Played follows Playing Now, and shows on its own once nothing plays; never the chosen player")
    func recentlyPlayedRows() {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        status.setActiveSources([vlc, chrome])
        status.setActiveSources([chrome])
        sut.status = status
        reopen(sut)
        #expect(parts(sut) == ["card", "mediaPlayer", "snooze", "playingNow", "recentlyPlayed", "ignoredApps", "toolbar"])
        #expect(sut.model.listedRecentSources == [vlc])

        status.setActiveSources([])
        sut.status = status
        reopen(sut)
        #expect(parts(sut) == ["card", "mediaPlayer", "snooze", "recentlyPlayed", "ignoredApps", "toolbar"])
        #expect(sut.model.listedRecentSources == [chrome, vlc])

        // VLC chosen as the player meanwhile: its switch would only store it as ignored.
        status.playerOptions.append(PlayerOption(bundleID: vlc.id, name: "VLC", appURL: URL(fileURLWithPath: "/Applications/VLC.app")))
        status.chosenPlayerID = vlc.id
        sut.status = status
        reopen(sut)
        #expect(sut.model.listedRecentSources == [chrome])
    }

    @Test("the menu follows the status at once, but the apps listed stay as they were until it opens again; closing for an update's alert is at once")
    func listsWaitForTheNextOpening() async {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        status.setActiveSources([vlc])
        status.setActiveSources([]) // VLC played: under Recently Played
        sut.status = status
        reopen(sut)

        status.setActiveSources([vlc, chrome]) // VLC plays again, and Chrome
        sut.status = status
        #expect(sut.model.status == status)              // the card shows it
        #expect(sut.model.listedSources.isEmpty)         // no row moves under the pointer
        #expect(sut.model.listedRecentSources == [vlc])
        #expect(!parts(sut).contains("playingNow"))

        await sut.closeMenu()
        #expect(!sut.isMenuOpen)
        await sut.closeMenu() // closed already: at once
        reopen(sut)
        #expect(parts(sut).contains("playingNow") && !parts(sut).contains("recentlyPlayed"))
    }

    @Test("the app can bring the status up to date before the menu opens; a closed menu catches up as it opens")
    func updateBeforeOpening() {
        let sut = makeController()
        defer { sut.remove() }
        sut.open(showsPanel: false)
        #expect(log.calls == ["menuWillOpen"] && sut.isMenuOpen)
        sut.close()
        sut.status = readyStatus()
        #expect(sut.model.status != readyStatus()) // until it opens again
        sut.open(showsPanel: false)
        #expect(sut.model.status == readyStatus())
    }

    @Test("auto-pause off dims the icon, and the card says until when")
    func autoPauseOff() {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        status.autoPause = .snoozed("until 15:30")
        sut.status = status
        #expect(sut.statusItem.button?.appearsDisabled == true) // at once
        reopen(sut)
        #expect(sut.model.status.statusLine == "Auto-Pause is off until 15:30")
    }

    // MARK: - The music player

    @Test("the Media Player row opens the players beside the menu, under “Supported Apps”; one that isn't installed comes last and can't be chosen; choosing one closes them and keeps the menu open")
    func playerList() async throws {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        status.playerOptions = [
            PlayerOption(bundleID: "com.example.first", name: "First", appURL: URL(fileURLWithPath: "/Applications/First.app")),
            PlayerOption(bundleID: "com.example.second", name: "Second", appURL: nil),
            PlayerOption(bundleID: "com.example.third", name: "Third", appURL: URL(fileURLWithPath: "/Applications/Third.app")),
        ]
        status.chosenPlayerID = "com.example.first"
        sut.status = status
        reopen(sut)

        sut.perform(.openSide(.players))
        #expect(sut.model.isChoosingPlayer)
        #expect(playerRows(sut) == ["[Supported]", "First", "Third", "Second", "[Other]"])
        let players = sut.model.players.supportedApps
        #expect(players.map(\.isChosen) == [true, false, false])
        #expect(players.map(\.isEnabled) == [true, true, false])
        #expect(players.map(\.subtitle) == [nil, nil, "Not installed"])

        // Chosen in place (the user, 2026-10-18): the menu stays open, the list folds.
        sut.perform(.choosePlayer("com.example.third"))
        #expect(sut.isMenuOpen && !sut.model.isChoosingPlayer)
        await wait(for: 2, in: log)
        #expect(log.calls == ["menuWillOpen", "player com.example.third"])

        // Another of AutoHush's windows coming forward (one the choice opened) closes it, as a menu.
        // A hidden one becoming key doesn't, nor the menu bar item's own window
        // (as VoiceOver's press on a row makes it), nor one at the menu bar's level.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40), styleMask: .titled, backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        center.post(name: NSWindow.didBecomeKeyNotification, object: window)
        #expect(sut.isMenuOpen) // hidden
        window.orderFrontRegardless()
        #expect(!StatusMenuController.closesMenu(becomingKey: window, statusItemWindow: window))
        #expect(StatusMenuController.closesMenu(becomingKey: window, statusItemWindow: nil))
        window.level = .statusBar
        #expect(!StatusMenuController.closesMenu(becomingKey: window, statusItemWindow: nil))
        window.level = .normal
        center.post(name: NSWindow.didBecomeKeyNotification, object: window)
        #expect(!sut.isMenuOpen)

        reopen(sut)
        #expect(!sut.model.isChoosingPlayer) // closed again each time it opens
    }

    @Test("an app added through a check is offered under Other Apps, removable with Option held; Add an App… and Add a Web App… open their windows")
    func checkedApp() async throws {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        status.playerOptions = [
            PlayerOption(bundleID: "com.example.first", name: "First", appURL: URL(fileURLWithPath: "/Applications/First.app")),
            PlayerOption(bundleID: "com.example.checked", name: "Checked", appURL: URL(fileURLWithPath: "/Applications/Checked.app"),
                         kind: .checkedApp),
        ]
        status.chosenPlayerID = "com.example.first"
        sut.status = status
        reopen(sut)

        sut.perform(.openSide(.players))
        #expect(playerRows(sut) == ["[Supported]", "First", "[Other]", "Checked"])
        #expect(try row("Checked", in: sut).isRemovable)
        #expect(try !row("First", in: sut).isRemovable)
        for command in [StatusMenuCommand.removeAddedApp("com.example.checked"), .addApp, .addWebApp] {
            sut.perform(command)
            reopen(sut)
        }
        await wait(for: 6, in: log)
        #expect(log.calls.filter { $0 != "menuWillOpen" } == ["remove com.example.checked", "addApp", "addWebApp"])
    }

    @Test("an app added through a check that isn't installed now stays under Other Apps, last, dimmed and “Not installed”; a Chromium browser's web app says whose")
    func uninstalledCheckedApp() throws {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        var chromeApp = PlayerOption(bundleID: "com.google.Chrome.app.sc", name: "SoundCloud",
                                     appURL: URL(fileURLWithPath: "/Users/test/Applications/Chrome Apps.localized/SoundCloud.app"),
                                     kind: .checkedApp)
        chromeApp.browserName = "Google Chrome"
        status.playerOptions = [
            PlayerOption(bundleID: "com.example.first", name: "First", appURL: URL(fileURLWithPath: "/Applications/First.app")),
            PlayerOption(bundleID: "com.example.gone", name: "Gone", appURL: nil, kind: .checkedApp),
            chromeApp,
        ]
        status.chosenPlayerID = "com.example.gone"
        sut.status = status
        reopen(sut)

        sut.perform(.openSide(.players))
        #expect(playerRows(sut) == ["[Supported]", "First", "[Other]", "SoundCloud", "Gone"])
        let gone = try row("Gone", in: sut)
        #expect(!gone.isEnabled && gone.isChosen)
        #expect(gone.subtitle == "Not installed")
        let soundCloud = try row("SoundCloud", in: sut)
        #expect(soundCloud.isEnabled)
        #expect(soundCloud.accessibilityLabel == "SoundCloud, Google Chrome web app")
    }

    @Test("an app that can only be muted says so; in AntiDot mode it's dimmed, saying why, and stays checked when chosen")
    func mutedOnlyAppInAntiDotMode() throws {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        var muted = PlayerOption(bundleID: "com.example.muted", name: "Muted", appURL: URL(fileURLWithPath: "/Applications/Muted.app"),
                                 kind: .checkedApp)
        muted.pausesByMuting = true
        muted.needsAudioLevels = true
        status.playerOptions = [
            PlayerOption(bundleID: "com.example.first", name: "First", appURL: URL(fileURLWithPath: "/Applications/First.app")),
            muted,
        ]
        status.chosenPlayerID = muted.bundleID
        sut.status = status
        reopen(sut)
        sut.perform(.openSide(.players))
        let shown = try row("Muted", in: sut)
        #expect(shown.isEnabled && shown.isChosen)
        #expect(shown.subtitle == "Muted instead of paused")
        #expect(shown.help == nil)

        settings.setDetectionMethod(.playbackSignals)
        reopen(sut)
        sut.perform(.openSide(.players))
        let dimmed = try row("Muted", in: sut)
        #expect(!dimmed.isEnabled && dimmed.isChosen)
        #expect(dimmed.subtitle == "Not in AntiDot mode")
        #expect(dimmed.help == muted.antiDotModeReason)
        #expect(try row("First", in: sut).isEnabled)
    }

    @Test("a suggested web app is offered after the web apps, can be chosen, and says how")
    func suggestedWebApp() throws {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        let suggestion = PlayerOption.suggestion(WebAppSuggestion(name: "Deezer", address: "deezer.com"))
        status.playerOptions = [
            PlayerOption(bundleID: "com.example.first", name: "First", appURL: URL(fileURLWithPath: "/Applications/First.app")),
            suggestion,
        ]
        status.chosenPlayerID = "com.example.first"
        sut.status = status
        reopen(sut)

        sut.perform(.openSide(.players))
        #expect(playerRows(sut) == ["[Supported]", "First", "[Other]", "[Web]", "Deezer"])
        let deezer = try row("Deezer", in: sut)
        #expect(deezer.isEnabled)
        #expect(deezer.subtitle == "Click to add") // as its tile says
    }

    @Test("a web app's controls are learned from the card's Controls row; nothing else in the menu is about learning")
    func learnControls() async throws {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        let webApp = PlayerOption(bundleID: "com.apple.Safari.WebApp.TEST", name: "YT Music",
                                  appURL: URL(fileURLWithPath: "/Applications/Safari.app"), kind: .safariWebApp)
        status.playerOptions = [
            PlayerOption(bundleID: "com.example.first", name: "First", appURL: URL(fileURLWithPath: "/Applications/First.app")),
            webApp,
        ]
        status.chosenPlayerID = webApp.bundleID
        for learning in [LearningStatus.learned, .learning(hasPlayed: false), .learning(hasPlayed: true)] {
            status.learning = learning
            sut.status = status
            reopen(sut)
            #expect(sut.model.status.canLearnControlsAgain) // the card shows its Controls row
            #expect(parts(sut) == ["card", "mediaPlayer", "snooze", "ignoredApps", "toolbar"])
        }

        // Its button: the menu closes, and a new learning window opens.
        sut.perform(.learnControls)
        await wait(for: 4, in: log)
        #expect(log.calls.suffix(1) == ["learnAgain"])

        // A player that learns nothing has no Controls row.
        status.chosenPlayerID = "com.example.first"
        status.learning = nil
        sut.status = status
        reopen(sut)
        #expect(!sut.model.status.canLearnControlsAgain)
    }

    @Test("an untested web app comes last, with an “Untested” badge VoiceOver reads; a web app named as an app is says it's a Safari web app")
    func untestedWebApp() throws {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        var untested = PlayerOption(bundleID: "com.apple.Safari.WebApp.U", name: "SoundCloud",
                                    appURL: URL(fileURLWithPath: "/Applications/SoundCloud.app"), kind: .safariWebApp)
        untested.isUntested = true
        var named = PlayerOption(bundleID: "com.apple.Safari.WebApp.M", name: "First",
                                 appURL: URL(fileURLWithPath: "/Applications/First Web.app"), kind: .safariWebApp)
        named.isUntested = true
        status.playerOptions = [
            PlayerOption(bundleID: "com.example.first", name: "First", appURL: URL(fileURLWithPath: "/Applications/First.app")),
            untested,
            named,
            .suggestion(WebAppSuggestion(name: "Deezer", address: "deezer.com")),
        ]
        sut.status = status
        reopen(sut)
        sut.perform(.openSide(.players))
        let web = sut.model.players.webApps
        #expect(web.map(\.option.name) == ["Deezer", "SoundCloud", "First"])
        #expect(web[1].accessibilityLabel == "SoundCloud, Untested")
        #expect(web[2].accessibilityLabel == "First, Safari web app, Untested")
        #expect(sut.model.players.supportedApps[0].accessibilityLabel == "First")
    }

    @Test("from eight players on, a search comes first and narrows them down; fewer have none; Return with nothing highlighted chooses the first one left, only while something is typed")
    func playerSearch() async {
        let sut = makeController()
        defer { sut.remove() }
        let names = ["Spotify", "Apple Music", "VLC", "Apple Podcasts", "TIDAL", "Qobuz", "Deezer", "Música"]
        var status = readyStatus()
        status.playerOptions = names.map {
            PlayerOption(bundleID: "com.example.\($0)", name: $0, appURL: $0 == "Deezer" ? nil : URL(fileURLWithPath: "/Applications/\($0).app"))
        }
        sut.status = status
        reopen(sut)

        sut.perform(.openSide(.players))
        #expect(playerRows(sut).prefix(10) == ["search", "[Supported]", "Spotify", "Apple Music", "VLC", "Apple Podcasts", "TIDAL",
                                               "Qobuz", "Música", "Deezer"])
        sut.perform(.searchPlayers("MUSI"))
        #expect(sut.model.playerSearch == "MUSI")
        #expect(playerRows(sut) == ["search", "[Supported]", "Apple Music", "Música"])
        sut.perform(.searchPlayers("zz"))
        #expect(playerRows(sut) == ["search", "No players match “zz”."])

        sut.perform(.searchPlayers(""))
        sut.perform(.chooseHighlighted) // nothing typed: nothing chosen
        #expect(sut.model.isChoosingPlayer)
        sut.perform(.searchPlayers("music"))
        sut.perform(.chooseHighlighted)
        await wait(for: 2, in: log)
        #expect(log.calls == ["menuWillOpen", "player com.example.Apple Music"])

        reopen(sut)
        sut.perform(.openSide(.players))
        sut.perform(.searchPlayers("vl"))
        sut.handle(.left) // closed: what was typed goes with it
        #expect(sut.model.playerSearch.isEmpty)
        sut.perform(.searchPlayers("a")) // a closing field handing its text back changes nothing
        #expect(sut.model.playerSearch.isEmpty)

        status.playerOptions.removeLast()
        sut.status = status
        reopen(sut)
        sut.perform(.openSide(.players))
        #expect(playerRows(sut).first == "[Supported]") // seven: no search
    }

    @Test("among the players, ↑ ↓ move the side window's highlight through their rows and Return presses the one it's on, ← closes them; with the players folded, the other keys are the panel's")
    func playerKeys() async {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        status.playerOptions = ["First", "Second"].map {
            PlayerOption(bundleID: "com.example.\($0)", name: $0, appURL: URL(fileURLWithPath: "/Applications/\($0).app"))
        }
        sut.status = status
        reopen(sut)
        #expect(!sut.handleKey(MenuPanelTests.key(0)))

        sut.perform(.openSide(.players))
        #expect(sut.handleKey(MenuPanelTests.key(123))) // ←
        #expect(!sut.model.isChoosingPlayer)
        sut.perform(.openSide(.players))
        sut.handle(.returnKey) // nothing highlighted, nothing typed: nothing chosen
        #expect(sut.model.isChoosingPlayer)
        // Their rows, as the side window's views register them.
        let first = UUID(), second = UUID()
        sut.model.sideKeyboard.register(first, .init(frame: CGRect(x: 0, y: 0, width: 280, height: 22),
                                                     press: { sut.perform(.choosePlayer("com.example.First")) }))
        sut.model.sideKeyboard.register(second, .init(frame: CGRect(x: 0, y: 30, width: 280, height: 22),
                                                      press: { sut.perform(.choosePlayer("com.example.Second")) }))
        #expect(sut.handleKey(MenuPanelTests.key(125))) // ↓
        #expect(sut.model.sideKeyboard.highlighted == first)
        #expect(sut.model.keyboard.highlighted == nil) // the menu's stays where it was
        #expect(sut.handleKey(MenuPanelTests.key(125)))
        #expect(sut.handleKey(MenuPanelTests.key(126))) // ↑
        #expect(sut.model.sideKeyboard.highlighted == first)
        #expect(!sut.handleKey(MenuPanelTests.key(0))) // A: not the list's
        sut.perform(.moveHighlight(1)) // as the search field's ↓ sends it
        #expect(sut.model.sideKeyboard.highlighted == second)
        sut.perform(.moveHighlight(-1))
        #expect(sut.handleKey(MenuPanelTests.key(36))) // Return
        await wait(for: 2, in: log)
        #expect(log.calls == ["menuWillOpen", "player com.example.First"])
    }

    @Test("elsewhere the keys work as in macOS's menus, whatever the keyboard navigation setting: ↑ ↓ move the highlight, Return or Space presses, ← → adjust, → opens a side window on its first row and ← closes it, keys with nothing to act on don't beep, Tab leaves it to the focus")
    func menuKeys() async {
        final class Log { var calls: [String] = [] }
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        status.ignoredApps = [vlc]
        sut.status = status
        reopen(sut)
        let calls = Log()
        let keyboard = sut.model.keyboard
        let slider = UUID(), sideRow = UUID(), appRow = UUID(), addRow = UUID()
        keyboard.register(slider, .init(frame: CGRect(x: 0, y: 0, width: 300, height: 20), adjust: { calls.calls.append("adjust \($0)") }))
        keyboard.register(sideRow, .init(frame: CGRect(x: 0, y: 40, width: 300, height: 20),
                                         press: { sut.perform(.openSide(.ignoredApps)) }, opensSide: true))

        #expect(sut.handleKey(MenuPanelTests.key(125))) // ↓: the first
        #expect(keyboard.highlighted == slider)
        #expect(sut.handleKey(MenuPanelTests.key(36))) // Return: nothing to press, and no beep
        #expect(sut.handleKey(MenuPanelTests.key(124))) // →
        #expect(sut.handleKey(MenuPanelTests.key(123))) // ←
        #expect(calls.calls == ["adjust 1", "adjust -1"])
        #expect(sut.handleKey(MenuPanelTests.key(125)))
        #expect(sut.handleKey(MenuPanelTests.key(124))) // → opens its side window
        #expect(sut.model.openSide == .ignoredApps)

        // Its rows, as its views register them: the first lights up once they've come.
        sut.model.sideKeyboard.register(addRow, .init(frame: CGRect(x: 0, y: 40, width: 280, height: 30), press: { calls.calls.append("add") }))
        sut.model.sideKeyboard.register(appRow, .init(frame: CGRect(x: 0, y: 0, width: 280, height: 30), press: { calls.calls.append("app") }))
        await TestWait.until { sut.model.sideKeyboard.highlighted == appRow }
        #expect(keyboard.highlighted == sideRow)
        #expect(sut.handleKey(MenuPanelTests.key(125))) // ↓ goes on from it
        #expect(sut.model.sideKeyboard.highlighted == addRow)
        #expect(sut.handleKey(MenuPanelTests.key(49))) // Space
        #expect(calls.calls.last == "add")
        #expect(sut.handleKey(MenuPanelTests.key(123))) // ← closes it
        #expect(sut.model.openSide == nil)
        #expect(sut.model.sideKeyboard.highlighted == nil)
        #expect(keyboard.highlighted == sideRow)

        // One the pointer opened: → lights its first row.
        sut.perform(.openSide(.ignoredApps))
        sut.model.sideKeyboard.register(appRow, .init(frame: CGRect(x: 0, y: 0, width: 280, height: 30), press: {}))
        #expect(sut.handleKey(MenuPanelTests.key(124)))
        #expect(sut.model.sideKeyboard.highlighted == appRow)
        sut.handle(.left)

        #expect(!sut.handleKey(MenuPanelTests.key(48))) // Tab: the keyboard's focus takes over
        #expect(keyboard.highlighted == nil)
        keyboard.move(1)
        reopen(sut) // a menu opens with nothing highlighted
        #expect(keyboard.highlighted == nil)
    }

    @Test("what a key types into the players' search: its characters, Delete one back, nothing for arrows, Return or shortcuts; a dead key or an input method needs the field itself")
    func typing() throws {
        func event(_ characters: String, ignoring: String? = nil, code: UInt16 = 0, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                                          characters: characters, charactersIgnoringModifiers: ignoring ?? characters,
                                          isARepeat: false, keyCode: code))
        }
        #expect(StatusMenuController.typedText(try event("é")) == "é")
        #expect(StatusMenuController.typedText(try event("\u{7f}", code: 51)) == "") // Delete
        #expect(StatusMenuController.typedText(try event("\u{F701}", code: 125)) == nil) // ↓
        #expect(StatusMenuController.typedText(try event("\r", code: 36)) == nil)
        #expect(StatusMenuController.typedText(try event("a", flags: .command)) == nil)
        #expect(!StatusMenuController.composes(try event("a"), inputMethod: false))
        #expect(StatusMenuController.composes(try event("", ignoring: "´", code: 39), inputMethod: false)) // a dead key
        #expect(StatusMenuController.composes(try event("k"), inputMethod: true))
        #expect(!StatusMenuController.composes(try event("\u{F701}", code: 125), inputMethod: true))
    }

    @Test("one key mapping for the menu and Settings: plain arrows, Return or Enter, Space, Tab with or without Shift; others, or with ⌘ ⌥ ⌃ ⇧, are the window's")
    func highlightKeys() {
        #expect(HighlightKey(keyCode: 125, modifiers: []) == .down)
        #expect(HighlightKey(keyCode: 126, modifiers: [.numericPad, .function]) == .up) // arrows carry these
        #expect(HighlightKey(keyCode: 76, modifiers: []) == .returnKey)
        #expect(HighlightKey(keyCode: 49, modifiers: []) == .space)
        #expect(HighlightKey(keyCode: 48, modifiers: .shift) == .tab)
        #expect(HighlightKey(keyCode: 125, modifiers: .command) == nil)
        #expect(HighlightKey(keyCode: 124, modifiers: .shift) == nil)
        #expect(HighlightKey(keyCode: 48, modifiers: .control) == nil)
        #expect(HighlightKey(keyCode: 0, modifiers: []) == nil)
    }

    @Test("Ignored Apps names one or two apps, then the first two and how many more", arguments: [
        ([String](), ""), (["VLC"], "VLC"), (["VLC", "Messages"], ListFormatter.localizedString(byJoining: ["VLC", "Messages"])),
        (["VLC", "Messages", "Chrome"], "VLC, Messages and 1 more"), (["VLC", "Messages", "Chrome", "Mail"], "VLC, Messages and 2 more"),
    ])
    func ignoredAppsNames(names: [String], expected: String) {
        #expect(MenuIgnoredAppsView.names(of: names) == expected)
    }

    @Test("resting the pointer on a row opens its side window; passing over it doesn't; another part closes it after a moment, its own part doesn't; a click opens it and never closes it")
    func sideWindowsOnHover() async {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        status.ignoredApps = [vlc]
        sut.status = status
        reopen(sut)

        sut.perform(.hoverSideRow(.players, true))
        sut.perform(.hoverSideRow(.players, false)) // only passing over it
        await sut.sideOpenTask?.value
        #expect(sut.model.openSide == nil)

        sut.perform(.hoverSideRow(.players, true))
        await sut.sideOpenTask?.value
        #expect(sut.model.openSide == .players)
        sut.perform(.pointerEntered(.mediaPlayer)) // its own part: stays
        sut.perform(.pointerEntered(.snooze))
        sut.perform(.pointerEntered(.mediaPlayer)) // back before the moment is over
        await sut.sideCloseTask?.value
        #expect(sut.model.openSide == .players)
        sut.perform(.pointerEntered(.settings))
        await sut.sideCloseTask?.value
        #expect(sut.model.openSide == nil)

        sut.perform(.openSide(.ignoredApps))
        sut.perform(.openSide(.ignoredApps)) // a click on its row again: still open
        #expect(sut.model.openSide == .ignoredApps && sut.model.listedIgnoredApps == [vlc])
        sut.perform(.hoverSideRow(.players, true)) // the other row
        await sut.sideOpenTask?.value
        #expect(sut.model.openSide == .players)
    }

    @Test("a pointer heading to the side window across other parts keeps it open until it's in; one resting, or moving away, closes it")
    func safeTriangle() async {
        @MainActor final class Pointer { var path: [CGPoint] = []; var step = 0 }
        let sut = makeController()
        defer { sut.remove() }
        sut.status = readyStatus()
        reopen(sut)
        let menu = CGRect(x: 1000, y: 200, width: 345, height: 700), side = CGRect(x: 694, y: 400, width: 300, height: 400)
        sut.windowFrames = { (menu, side) }
        let pointer = Pointer()
        // Where the pointer is after each of the timing's waits.
        sut.pointerLocation = { pointer.path[min(pointer.step, pointer.path.count - 1)] }
        sut.pause = { _ in await MainActor.run { pointer.step += 1 } }

        for (path, staysOpen) in [([CGPoint(x: 1100, y: 600), CGPoint(x: 1050, y: 600), CGPoint(x: 990, y: 600)], true), // into it
                                  ([CGPoint(x: 1100, y: 600)], false), // resting
                                  ([CGPoint(x: 1100, y: 600), CGPoint(x: 1150, y: 600)], false)] { // away
            sut.perform(.openSide(.players))
            pointer.path = path
            pointer.step = 0
            sut.perform(.pointerEntered(.snooze))
            await sut.sideCloseTask?.value
            #expect((sut.model.openSide == .players) == staysOpen, "\(path)")
            sut.handle(.left)
        }
    }

    @Test("going to another desktop closes the menu")
    func desktopChange() {
        let sut = makeController()
        defer { sut.remove() }
        sut.status = readyStatus()
        reopen(sut)
        #expect(sut.isMenuOpen)
        workspaceCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: NSWorkspace.shared)
        #expect(!sut.isMenuOpen)
    }

    // MARK: - The settings

    @Test("the settings' switches always show; each part's title unfolds its other settings on its own, and they stay as left when the menu opens again; folding, they fade out first, and a click meanwhile keeps them")
    func moreSettings() async {
        let settingsModel = SettingsModel(settings: settings, updates: updates, actions: actions,
                                          launchAtLoginController: MockLaunchAtLoginController(isEnabled: false))
        let sut = makeController(settingsModel: settingsModel)
        defer { sut.remove() }
        sut.status = readyStatus()
        reopen(sut)
        #expect(parts(sut).contains("settings") && sut.model.unfoldedSettings.isEmpty)
        sut.perform(.toggleSettings(.detection))
        reopen(sut)
        #expect(sut.model.unfoldedSettings == [.detection]) // kept, unlike the players' list
        sut.perform(.toggleSettings(.fades))
        #expect(sut.model.unfoldedSettings == [.detection, .fades])
        sut.perform(.toggleSettings(.detection))
        #expect(sut.model.foldingSettings == [.detection]) // fading out, still there
        sut.perform(.toggleSettings(.detection)) // clicked again meanwhile: it stays
        #expect(sut.foldTasks[.detection] == nil)
        #expect(sut.model.unfoldedSettings == [.detection, .fades] && sut.model.foldingSettings.isEmpty)
        sut.perform(.toggleSettings(.detection))
        sut.perform(.toggleSettings(.detection))
        sut.perform(.toggleSettings(.detection)) // folding again: its own fade, whole
        #expect(sut.model.foldingSettings == [.detection] && sut.model.unfoldedSettings.contains(.detection))
        await sut.foldTasks[.detection]?.value
        #expect(sut.model.unfoldedSettings == [.fades] && sut.model.foldingSettings.isEmpty && sut.isMenuOpen)

        // With Reduce Motion: folded at once, no fade.
        sut.reducesMotion = { true }
        sut.perform(.toggleSettings(.fades))
        #expect(sut.model.unfoldedSettings.isEmpty && sut.model.foldingSettings.isEmpty)
        sut.perform(.toggleSettings(.fades))
        #expect(sut.model.unfoldedSettings == [.fades])
        #expect(log.calls.allSatisfy { $0 == "menuWillOpen" })
    }

    @Test("the menu reads AntiDot mode live from the settings, so the players follow its switch in the menu at once")
    func antiDotModeLive() {
        let settingsModel = SettingsModel(settings: settings, updates: updates, actions: actions,
                                          launchAtLoginController: MockLaunchAtLoginController(isEnabled: false))
        let sut = makeController(settingsModel: settingsModel)
        defer { sut.remove() }
        sut.status = readyStatus()
        reopen(sut)
        #expect(!sut.model.isAntiDotMode)
        settings.setDetectionMethod(.playbackSignals)
        #expect(sut.model.isAntiDotMode) // without opening the menu again
        settings.setDetectionMethod(.audioLevels)
        #expect(!sut.model.isAntiDotMode)
    }

    @Test("a window shows less than its content only when the screen caps it: then the menu says more is below")
    func cappedByScreen() {
        #expect(StatusMenuController.isCapped(height: 600, content: 700))
        #expect(!StatusMenuController.isCapped(height: 700, content: 700.3))
        #expect(!StatusMenuController.isCapped(height: 700, content: 650))
    }

    @Test("a click on the menu bar item closes the open menu")
    func iconClosesMenu() {
        let sut = makeController()
        defer { sut.remove() }
        sut.open(showsPanel: false)
        sut.statusItemClicked()
        #expect(!sut.isMenuOpen)
    }

    // MARK: - Commands

    @Test("switches and folding act at once and keep the menu open")
    func switches() {
        let sut = makeController()
        defer { sut.remove() }
        sut.open(showsPanel: false)
        // As the menu's views send them.
        sut.model.perform(.toggleAutoPause)
        sut.model.perform(.setIgnored(chrome, true))
        sut.model.perform(.openSide(.ignoredApps))
        #expect(settings.state.autoPause == .off)
        #expect(settings.state.ignoredApps.map(\.id) == [chrome.id])
        #expect(sut.model.showsIgnoredApps && sut.isMenuOpen)
        #expect(log.calls == ["menuWillOpen"])
    }

    @Test("buttons close the menu, then act")
    func buttons() async {
        let sut = makeController()
        defer { sut.remove() }
        let commands: [StatusMenuCommand] = [.snooze(.oneHour), .openSettings, .showDiagnostics, .showAbout,
                                             .showControlError, .reopenPlayer, .unmutePlayer, .quit]
        commands.forEach { sut.model.perform($0) } // as the menu's views send them
        #expect(log.calls.isEmpty) // not yet: the menu closes first
        #expect(settings.state.autoPause == .on)
        await wait(for: commands.count - 1, in: log)
        #expect(log.calls == ["settings", "diagnostics", "about", "why", "reopenPlayer", "unmutePlayer", "quit"])
        guard case .snoozed = settings.state.autoPause else {
            Issue.record("not snoozed: \(settings.state.autoPause)")
            return
        }
    }

    @Test("Updates checks with the menu open, its button saying Checking… until the result; asked again meanwhile, nothing more")
    func updatesChecksInTheMenu() async {
        let sut = makeController()
        defer { sut.remove() }
        sut.status = readyStatus()
        updates.holdsChecks = true
        sut.perform(.updates)
        #expect(sut.model.isCheckingForUpdates)
        await wait(for: 1, in: log)
        sut.perform(.updates) // a second click while it checks
        #expect(log.calls == ["checkNow"])

        updates.finishCheck()
        await TestWait.until { !sut.model.isCheckingForUpdates }
        #expect(!sut.model.isCheckingForUpdates)
        #expect(log.calls == ["checkNow"])
    }

    @Test("once an update is found, Updates shows it instead of checking again")
    func updatesShowsTheOffer() async {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        let release = AppRelease(version: AppVersion("0.3.0")!, pageURL: URL(string: "https://example.com")!)
        status.updateOffer = UpdateOffer(release: release, state: .available)
        sut.status = status
        sut.perform(.updates)
        await wait(for: 1, in: log)
        #expect(log.calls == ["update"])
    }

    @Test("the menu bar icon shows the update badge while an update waits, drawn as it is")
    func iconShowsUpdate() {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        sut.status = status
        #expect(sut.statusItem.button?.image?.size == MenuBarIcon.size)
        let release = AppRelease(version: AppVersion("0.3.0")!, pageURL: URL(string: "https://example.com")!)
        status.updateOffer = UpdateOffer(release: release, state: .downloaded)
        sut.status = status
        #expect(sut.statusItem.button?.image?.size == MenuBarIcon.updateSize)
        #expect(sut.statusItem.button?.imageScaling == .scaleNone)
        #expect(sut.statusItem.button?.image?.accessibilityDescription == status.iconAccessibilityLabel)
        status.updateOffer = nil
        sut.status = status
        #expect(sut.statusItem.button?.image?.size == MenuBarIcon.size)
    }

    @Test("Retry tries again at once and keeps the menu open; VoiceOver hears how it went")
    func retry() {
        let sut = makeController()
        defer { sut.remove() }
        #expect(session.state.health == nil) // no player chosen
        sut.perform(.retry)
        #expect(session.state.health == .starting)
        #expect(sut.model.announcesRetryOutcome)
    }

    // MARK: - Rows

    @Test("Ignored Apps shows with none too; its row opens its side window, each app with its switch; one switched back on keeps its row while it's open; one side window at a time")
    func ignoredApps() {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        status.setActiveSources([vlc, chrome])
        sut.status = status
        reopen(sut)
        #expect(parts(sut).contains("ignoredApps")) // none yet: the first is added from it

        status.ignoredApps = [vlc]
        sut.status = status
        #expect(parts(sut) == ["card", "mediaPlayer", "snooze", "playingNow", "ignoredApps", "toolbar"])
        #expect(sut.model.openSide == nil)
        sut.perform(.openSide(.ignoredApps))
        #expect(sut.model.openSide == .ignoredApps && sut.model.listedIgnoredApps == [vlc])
        settings.setIgnored(vlc, true)
        sut.perform(.setIgnored(vlc, false)) // as its switch sends it
        #expect(settings.state.ignoredApps.isEmpty && sut.isMenuOpen)

        status.ignoredApps = []
        sut.status = status
        #expect(sut.model.listedIgnoredApps == [vlc]) // its side window keeps its row
        sut.perform(.openSide(.players)) // the players' instead
        #expect(sut.model.openSide == .players)
        #expect(parts(sut).contains("ignoredApps"))
        reopen(sut)
        #expect(sut.model.openSide == nil) // closed each time the menu opens
    }

    @Test("once the user went to allow audio recording, its row reopens AutoHush, and AntiDot mode is offered instead")
    func reopenRow() async {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        status.detection = .unavailable
        status.awaitsReopenForAudioRecording = true
        sut.status = status
        reopen(sut)

        #expect(parts(sut).prefix(5) == ["card", "mediaPlayer", "Reopen AutoHush", "Use AntiDot Mode Instead", "snooze"])
        sut.perform(.reopenAutoHush)
        sut.perform(.useAntiDotMode)
        await TestWait.until { settings.state.detection == .playbackSignals }
        #expect(log.calls == ["menuWillOpen", "reopen"])
    }

    @Test("a warning appears under the card as one row that asks for what's missing")
    func warningRow() async {
        let sut = makeController()
        defer { sut.remove() }
        var status = AppStatus()
        status.choosePlayer(named: "Jukebox")
        status.setHealth(.needsPermission(.automation(player: "Jukebox")))
        sut.status = status
        reopen(sut)

        #expect(parts(sut).prefix(4) == ["card", "mediaPlayer", "Allow Jukebox Automation Access…", "snooze"])
        sut.perform(.resolveWarning(.automation(player: "Jukebox")))
        await wait(for: 2, in: log)
        #expect(log.calls == ["menuWillOpen", "warning Allow Jukebox Automation Access…"])
    }

    @Test("once an update is found, a row above the toolbar shows it", arguments: [UpdateOffer.State.available, .downloaded, .installing])
    func updateRow(state: UpdateOffer.State) async {
        let sut = makeController()
        defer { sut.remove() }
        let release = AppRelease(version: AppVersion("0.3.0")!, pageURL: URL(string: "https://example.com")!)
        var status = readyStatus()
        status.updateOffer = UpdateOffer(release: release, state: state)
        sut.status = status
        reopen(sut)
        #expect(parts(sut).suffix(2) == ["update", "toolbar"])
        sut.perform(.showUpdate)
        await wait(for: 2, in: log)
        #expect(log.calls == ["menuWillOpen", "update"])
    }
}
