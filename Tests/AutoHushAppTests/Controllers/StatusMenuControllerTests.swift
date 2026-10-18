import AppKit
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

/// One test at a time: some post system-wide notifications (another
/// desktop, another window becoming key) that close every open menu.
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

    private func makeController(settingsModel: SettingsModel? = nil) -> StatusMenuController {
        StatusMenuController(settings: settings, session: session, updates: updates, actions: actions, settingsModel: settingsModel)
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

    @Test("the menu is the card, the duration buttons and the toolbar; playing and ignored apps and the settings add their parts")
    func layout() {
        let sut = makeController()
        defer { sut.remove() }
        sut.status = readyStatus()
        reopen(sut)
        #expect(parts(sut) == ["card", "mediaPlayer", "snooze", "toolbar"])

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
        #expect(parts(withSettings) == ["card", "mediaPlayer", "snooze", "settings", "toolbar"])
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
        #expect(parts(sut) == ["card", "mediaPlayer", "snooze", "playingNow", "recentlyPlayed", "toolbar"])
        #expect(sut.model.listedRecentSources == [vlc])

        status.setActiveSources([])
        sut.status = status
        reopen(sut)
        #expect(parts(sut) == ["card", "mediaPlayer", "snooze", "recentlyPlayed", "toolbar"])
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

    @Test("the Media player row unfolds the players under it, under “Supported Apps”; one that isn't installed comes last and can't be chosen; choosing one folds them and keeps the menu open")
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

        sut.perform(.togglePlayerList)
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
        // The menu bar item's own window or a hidden one becoming key (as VoiceOver's
        // press on a row makes it) doesn't.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40), styleMask: .titled, backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        #expect(sut.isMenuOpen) // hidden
        #expect(!StatusMenuController.closesMenu(becomingKey: window, statusItemWindow: window))
        window.orderFrontRegardless()
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        #expect(!sut.isMenuOpen)

        reopen(sut)
        #expect(!sut.model.isChoosingPlayer) // folded again each time it opens
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

        sut.perform(.togglePlayerList)
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

        sut.perform(.togglePlayerList)
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
        sut.perform(.togglePlayerList)
        let shown = try row("Muted", in: sut)
        #expect(shown.isEnabled && shown.isChosen)
        #expect(shown.subtitle == "Muted instead of paused")
        #expect(shown.help == nil)

        settings.setDetectionMethod(.playbackSignals)
        reopen(sut)
        sut.perform(.togglePlayerList)
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

        sut.perform(.togglePlayerList)
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
            #expect(parts(sut) == ["card", "mediaPlayer", "snooze", "toolbar"])
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
        sut.perform(.togglePlayerList)
        let web = sut.model.players.webApps
        #expect(web.map(\.option.name) == ["Deezer", "SoundCloud", "First"])
        #expect(web[1].accessibilityLabel == "SoundCloud, Untested")
        #expect(web[2].accessibilityLabel == "First, Safari web app, Untested")
        #expect(sut.model.players.supportedApps[0].accessibilityLabel == "First")
    }

    @Test("from eight players on, a search comes first and narrows them down; fewer have none; ↑ ↓ move among them and Return chooses")
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

        sut.perform(.togglePlayerList)
        #expect(playerRows(sut).prefix(10) == ["search", "[Supported]", "Spotify", "Apple Music", "VLC", "Apple Podcasts", "TIDAL",
                                               "Qobuz", "Música", "Deezer"])
        sut.perform(.searchPlayers("MUSI"))
        #expect(sut.model.playerSearch == "MUSI")
        #expect(playerRows(sut) == ["search", "[Supported]", "Apple Music", "Música"])
        sut.perform(.searchPlayers("zz"))
        #expect(playerRows(sut) == ["search", "No players match “zz”."])

        // The arrows stop at the ends, and skip a player that can't be chosen.
        sut.perform(.searchPlayers(""))
        sut.perform(.moveHighlight(-1))
        #expect(sut.model.highlightedPlayerID == "com.example.Música") // the last choosable: not Deezer
        sut.perform(.moveHighlight(1))
        #expect(sut.model.highlightedPlayerID == "com.example.Música")
        sut.perform(.searchPlayers("music"))
        sut.perform(.moveHighlight(-1))
        #expect(sut.model.highlightedPlayerID == "com.example.Apple Music")
        sut.perform(.chooseHighlighted)
        await wait(for: 2, in: log)
        #expect(log.calls == ["menuWillOpen", "player com.example.Apple Music"])

        reopen(sut)
        sut.perform(.togglePlayerList)
        sut.perform(.searchPlayers("vl"))
        sut.perform(.togglePlayerList) // folded: what was typed goes with it
        #expect(sut.model.playerSearch.isEmpty)
        sut.perform(.searchPlayers("a")) // a closing field handing its text back changes nothing
        #expect(sut.model.playerSearch.isEmpty)

        status.playerOptions.removeLast()
        sut.status = status
        reopen(sut)
        sut.perform(.togglePlayerList)
        #expect(playerRows(sut).first == "[Supported]") // seven: no search
    }

    @Test("in the panel, ↑ ↓ move among the unfolded players and Return chooses, ← closes them; with the players folded, the other keys are the panel's")
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

        sut.perform(.togglePlayerList)
        #expect(sut.handleKey(MenuPanelTests.key(123))) // ←
        #expect(!sut.model.isChoosingPlayer)
        sut.perform(.togglePlayerList)
        #expect(sut.handleKey(MenuPanelTests.key(125))) // ↓
        #expect(sut.model.highlightedPlayerID == "com.example.First")
        #expect(sut.handleKey(MenuPanelTests.key(125)))
        #expect(sut.handleKey(MenuPanelTests.key(126))) // ↑
        #expect(sut.model.highlightedPlayerID == "com.example.First")
        #expect(!sut.handleKey(MenuPanelTests.key(0))) // A: not the list's
        #expect(sut.handleKey(MenuPanelTests.key(36))) // Return
        await wait(for: 2, in: log)
        #expect(log.calls == ["menuWillOpen", "player com.example.First"])
    }

    @Test("elsewhere the keys work as in macOS's menus, whatever the keyboard navigation setting: ↑ ↓ move the highlight, Return or Space presses, ← → adjust, → opens a side window and ← closes it, Tab leaves it to the focus")
    func menuKeys() {
        final class Log { var calls: [String] = [] }
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        status.ignoredApps = [vlc]
        sut.status = status
        reopen(sut)
        let calls = Log()
        let keyboard = sut.model.keyboard
        let slider = UUID(), sideRow = UUID(), appRow = UUID()
        keyboard.register(slider, .init(frame: CGRect(x: 0, y: 0, width: 300, height: 20), adjust: { calls.calls.append("adjust \($0)") }))
        keyboard.register(sideRow, .init(frame: CGRect(x: 0, y: 40, width: 300, height: 20),
                                         press: { sut.perform(.openSide(.ignoredApps)) }, opensSide: true))

        #expect(sut.handleKey(MenuPanelTests.key(125))) // ↓: the first
        #expect(keyboard.highlighted == slider)
        #expect(!sut.handleKey(MenuPanelTests.key(36))) // Return: nothing to press
        #expect(sut.handleKey(MenuPanelTests.key(124))) // →
        #expect(sut.handleKey(MenuPanelTests.key(123))) // ←
        #expect(calls.calls == ["adjust 1", "adjust -1"])
        #expect(sut.handleKey(MenuPanelTests.key(125)))
        #expect(sut.handleKey(MenuPanelTests.key(124))) // → opens its side window
        #expect(sut.model.openSide == .ignoredApps)

        sut.model.sideKeyboard.register(appRow, .init(frame: CGRect(x: 0, y: 0, width: 280, height: 30), press: { calls.calls.append("app") }))
        #expect(sut.handleKey(MenuPanelTests.key(125))) // into the side window's rows
        #expect(sut.model.sideKeyboard.highlighted == appRow)
        #expect(keyboard.highlighted == sideRow)
        #expect(sut.handleKey(MenuPanelTests.key(49))) // Space
        #expect(calls.calls.last == "app")
        #expect(sut.handleKey(MenuPanelTests.key(123))) // ← closes it
        #expect(sut.model.openSide == nil)
        #expect(sut.model.sideKeyboard.highlighted == nil)
        #expect(keyboard.highlighted == sideRow)

        #expect(!sut.handleKey(MenuPanelTests.key(48))) // Tab: the keyboard's focus takes over
        #expect(keyboard.highlighted == nil)
        keyboard.move(1)
        reopen(sut) // a menu opens with nothing highlighted
        #expect(keyboard.highlighted == nil)
    }

    @Test("Ignored Apps names one or two apps, then the first two and how many more")
    func ignoredAppsNames() {
        #expect(MenuIgnoredAppsView.names(of: []) == "")
        #expect(MenuIgnoredAppsView.names(of: ["VLC"]) == "VLC")
        #expect(MenuIgnoredAppsView.names(of: ["VLC", "Messages"]) == ListFormatter.localizedString(byJoining: ["VLC", "Messages"]))
        #expect(MenuIgnoredAppsView.names(of: ["VLC", "Messages", "Chrome"]) == "VLC, Messages and 1 more")
        #expect(MenuIgnoredAppsView.names(of: ["VLC", "Messages", "Chrome", "Mail"]) == "VLC, Messages and 2 more")
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
        try? await Task.sleep(for: .seconds(StatusMenuController.sideOpenDelay + 0.1))
        #expect(sut.model.openSide == nil)

        sut.perform(.hoverSideRow(.players, true))
        await TestWait.until { sut.model.openSide == .players }
        sut.perform(.pointerEntered(.mediaPlayer)) // its own part: stays
        sut.perform(.pointerEntered(.snooze))
        sut.perform(.pointerEntered(.mediaPlayer)) // back before the moment is over
        try? await Task.sleep(for: .seconds(StatusMenuController.sideCloseDelay + 0.1))
        #expect(sut.model.openSide == .players)
        sut.perform(.pointerEntered(.settings))
        await TestWait.until { sut.model.openSide == nil }

        sut.perform(.openSide(.ignoredApps))
        sut.perform(.openSide(.ignoredApps)) // a click on its row again: still open
        #expect(sut.model.openSide == .ignoredApps && sut.model.listedIgnoredApps == [vlc])
        sut.perform(.hoverSideRow(.players, true)) // the other row
        await TestWait.until { sut.model.openSide == .players }
    }

    @Test("going to another desktop closes the menu")
    func desktopChange() {
        let sut = makeController()
        defer { sut.remove() }
        sut.status = readyStatus()
        reopen(sut)
        #expect(sut.isMenuOpen)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: NSWorkspace.shared)
        #expect(!sut.isMenuOpen)
    }

    // MARK: - The settings

    @Test("the settings' switches always show; each part's chevron unfolds its other settings on its own, and they stay as left when the menu opens again")
    func moreSettings() {
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
        #expect(sut.model.unfoldedSettings == [.fades] && sut.isMenuOpen)
        #expect(log.calls.allSatisfy { $0 == "menuWillOpen" })
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
        sut.model.perform(.toggleIgnoredApps)
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

    @Test("Ignored Apps' row opens its side window, each app with its switch; one switched back on keeps its row and the part while it's open; one side window at a time")
    func ignoredApps() {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        status.setActiveSources([vlc, chrome])
        sut.status = status
        reopen(sut)
        #expect(!parts(sut).contains("ignoredApps"))

        status.ignoredApps = [vlc]
        sut.status = status
        #expect(parts(sut) == ["card", "mediaPlayer", "snooze", "playingNow", "ignoredApps", "toolbar"])
        #expect(sut.model.openSide == nil)
        sut.perform(.toggleIgnoredApps)
        #expect(sut.model.openSide == .ignoredApps && sut.model.listedIgnoredApps == [vlc])
        settings.setIgnored(vlc, true)
        sut.perform(.setIgnored(vlc, false)) // as its switch sends it
        #expect(settings.state.ignoredApps.isEmpty && sut.isMenuOpen)

        status.ignoredApps = []
        sut.status = status
        #expect(parts(sut).contains("ignoredApps")) // its side window is open
        #expect(sut.model.listedIgnoredApps == [vlc]) // and keeps its row
        sut.perform(.togglePlayerList) // the players' instead
        #expect(sut.model.openSide == .players)
        #expect(!parts(sut).contains("ignoredApps"))
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
