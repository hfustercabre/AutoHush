import AppKit
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("StatusMenuController")
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

    private func makeController() -> StatusMenuController {
        StatusMenuController(settings: settings, session: session, updates: updates, actions: actions)
    }

    /// Ready to control the Jukebox player, paused for another app.
    private func readyStatus() -> AppStatus {
        var status = AppStatus()
        status.choosePlayer(named: "Jukebox")
        status.setHealth(.ready)
        status.playback = .pausedByMonitor
        return status
    }

    /// What macOS does before the menu opens: the menu is put together.
    private func prepareToOpen(_ sut: StatusMenuController) {
        sut.menuNeedsUpdate(sut.menu)
    }

    /// The visible rows: a custom view by its identifier, a separator as
    /// "—", any other row by its title.
    private func rows(_ menu: NSMenu) -> [String] {
        menu.items.filter { !$0.isHidden }.map { item in
            if item.isSeparatorItem { return "—" }
            return item.view == nil ? item.title : item.identifier?.rawValue ?? "view"
        }
    }

    private func item(_ title: String, in menu: NSMenu) throws -> NSMenuItem {
        try #require(menu.items.first { $0.title == title }, "no menu item \"\(title)\"")
    }

    private func perform(_ item: NSMenuItem) throws {
        let menu = try #require(item.menu)
        menu.performActionForItem(at: menu.index(of: item))
    }

    /// Waits until `log` has `count` calls: some commands run once the menu
    /// has closed.
    private func wait(for count: Int, in log: CallLog, sourceLocation: SourceLocation = #_sourceLocation) async {
        await TestWait.until(sourceLocation: sourceLocation) { log.calls.count >= count }
    }

    // MARK: - Layout

    @Test("the menu is the card, the duration buttons and the toolbar; playing and ignored apps add their parts")
    func layout() {
        let sut = makeController()
        defer { sut.remove() }
        sut.status = readyStatus()
        prepareToOpen(sut)
        #expect(rows(sut.menu) == ["card", "snooze", "—", "toolbar"])
        #expect(sut.menu.items.compactMap(\.view).allSatisfy { $0.frame.width >= menuContentWidth && $0.frame.height > 0 })

        var status = readyStatus()
        status.ignoredApps = [vlc]
        status.setActiveSources([vlc, chrome])
        sut.status = status
        prepareToOpen(sut)
        #expect(rows(sut.menu) == ["card", "snooze", "—", "playingApps", "—", "Ignored Apps", "—", "toolbar"])
        #expect(sut.model.listedSources == [chrome, vlc])
    }

    @Test("Recently Played follows Playing Now, and shows on its own once nothing plays; never the chosen player")
    func recentlyPlayedRows() {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        status.setActiveSources([vlc, chrome])
        status.setActiveSources([chrome])
        sut.status = status
        prepareToOpen(sut)
        #expect(rows(sut.menu) == ["card", "snooze", "—", "playingApps", "recentApps", "—", "toolbar"])
        #expect(sut.model.listedRecentSources == [vlc])

        status.setActiveSources([])
        sut.status = status
        prepareToOpen(sut)
        #expect(rows(sut.menu) == ["card", "snooze", "—", "recentApps", "—", "toolbar"])
        #expect(sut.model.listedRecentSources == [chrome, vlc])

        // VLC chosen as the player meanwhile: its switch would only store it as ignored.
        status.playerOptions.append(PlayerOption(bundleID: vlc.id, name: "VLC", appURL: URL(fileURLWithPath: "/Applications/VLC.app")))
        status.chosenPlayerID = vlc.id
        sut.status = status
        prepareToOpen(sut)
        #expect(sut.model.listedRecentSources == [chrome])
    }

    @Test("the views follow the status at once; rows are added or taken away only when the menu next opens; an update's alert waits for it to close")
    func rowsWaitForTheNextOpening() async {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        status.setActiveSources([vlc])
        status.setActiveSources([]) // VLC played: under Recently Played
        sut.status = status
        prepareToOpen(sut)
        sut.menuWillOpen(sut.menu)

        status.setActiveSources([vlc, chrome]) // VLC plays again, and Chrome
        sut.status = status
        #expect(sut.model.status == status)              // the card shows it
        #expect(sut.model.listedSources.isEmpty)         // no row moves under the pointer
        #expect(sut.model.listedRecentSources == [vlc])
        #expect(!rows(sut.menu).contains("playingApps"))

        // An update's alert shows once the menu has closed.
        let closed = CallLog()
        let closing = Task { await sut.closeMenu(); closed.calls.append("closed") }
        await Task.yield()
        #expect(closed.calls.isEmpty) // still open
        sut.menuDidClose(sut.menu)
        await closing.value
        #expect(!sut.isMenuOpen && closed.calls == ["closed"])
        await sut.closeMenu() // closed already: at once
        prepareToOpen(sut)
        #expect(rows(sut.menu).contains("playingApps") && !rows(sut.menu).contains("recentApps"))
    }

    @Test("the app can bring the status up to date before the menu opens")
    func updateBeforeOpening() {
        let sut = makeController()
        defer { sut.remove() }
        prepareToOpen(sut)
        #expect(log.calls == ["menuWillOpen"])
    }

    @Test("auto-pause off dims the icon, and the card says until when")
    func autoPauseOff() {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        status.autoPause = .snoozed("until 15:30")
        sut.status = status
        #expect(sut.statusItem.button?.appearsDisabled == true) // at once
        prepareToOpen(sut)
        #expect(sut.model.status.statusLine == "Auto-Pause is off until 15:30")
    }

    // MARK: - The music player

    @Test("the player button unfolds the players under the card, under “Supported Apps”; one that isn't installed comes last and can't be chosen; every icon shows")
    func playerList() throws {
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
        prepareToOpen(sut)

        sut.perform(.togglePlayerList)
        #expect(sut.model.isChoosingPlayer)
        #expect(rows(sut.menu).prefix(9) == ["card", "supportedAppsHeading", "First", "Third", "Second", "otherAppsHeading", "Add an App…",
                                             "Add a Web App…", "snooze"])
        let heading = sut.menu.items[1]
        #expect(heading.title == "Supported Apps")
        #expect(!heading.isEnabled)
        let players = Array(sut.menu.items[2...4])
        #expect(players.map(\.state) == [.on, .off, .off])
        #expect(players.map(\.isEnabled) == [true, true, false])
        #expect(players.map(\.subtitle) == [nil, nil, "Not installed"])
        #expect(players.allSatisfy { $0.image != nil })
        if #available(macOS 27, *) {
            // macOS 27 hides menu items' images unless they ask to show them.
            #expect((players + [try item("Add a Web App…", in: sut.menu)]).allSatisfy { $0.preferredImageVisibility == .visible })
        }
        try perform(players[1])
        #expect(log.calls == ["menuWillOpen", "player com.example.third"])

        sut.perform(.togglePlayerList)
        #expect(!sut.model.isChoosingPlayer)
        #expect(rows(sut.menu).prefix(2) == ["card", "snooze"])
    }

    @Test("an app added through a check is offered under Other Apps, before Add an App…, which opens its window, as Add a Web App… opens its own")
    func checkedApp() throws {
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
        prepareToOpen(sut)

        sut.perform(.togglePlayerList)
        #expect(rows(sut.menu).prefix(8) == ["card", "supportedAppsHeading", "First", "otherAppsHeading", "Checked", "Remove Checked…",
                                             "Add an App…", "Add a Web App…"])
        let heading = sut.menu.items[3]
        #expect(heading.title == "Other Apps")
        #expect(!heading.isEnabled)
        // Option held: its row removes it, after asking (R5).
        let remove = try item("Remove Checked…", in: sut.menu)
        #expect(remove.isAlternate && remove.keyEquivalentModifierMask == .option)
        try perform(remove)
        try perform(try item("Add an App…", in: sut.menu))
        try perform(try item("Add a Web App…", in: sut.menu))
        #expect(log.calls == ["menuWillOpen", "remove com.example.checked", "addApp", "addWebApp"])
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
        prepareToOpen(sut)

        sut.perform(.togglePlayerList)
        #expect(rows(sut.menu).prefix(9) == ["card", "supportedAppsHeading", "First", "otherAppsHeading", "SoundCloud",
                                             "Remove SoundCloud…", "Gone", "Remove Gone…", "Add an App…"])
        let gone = try item("Gone", in: sut.menu)
        #expect(!gone.isEnabled && gone.state == .on)
        #expect(gone.subtitle == "Not installed")
        let soundCloud = try item("SoundCloud", in: sut.menu)
        #expect(soundCloud.isEnabled)
        #expect(soundCloud.accessibilityLabel() == "SoundCloud, Google Chrome web app")
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
        prepareToOpen(sut)
        sut.perform(.togglePlayerList)
        let row = try item("Muted", in: sut.menu)
        #expect(row.isEnabled && row.state == .on)
        #expect(row.subtitle == "Muted instead of paused")
        #expect(row.toolTip == nil)

        settings.setDetectionMethod(.playbackSignals)
        prepareToOpen(sut)
        sut.perform(.togglePlayerList)
        let dimmed = try item("Muted", in: sut.menu)
        #expect(!dimmed.isEnabled && dimmed.state == .on)
        #expect(dimmed.subtitle == "Not in AntiDot mode")
        #expect(dimmed.toolTip == muted.antiDotModeReason)
        #expect(dimmed.accessibilityHelp() == muted.antiDotModeReason)
        #expect(try item("First", in: sut.menu).isEnabled)
    }

    @Test("a suggested web app is offered after the web apps, can be clicked, and goes the way a player does")
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
        prepareToOpen(sut)

        sut.perform(.togglePlayerList)
        #expect(rows(sut.menu).prefix(8) == ["card", "supportedAppsHeading", "First", "otherAppsHeading", "Add an App…",
                                             "webAppsHeading", "Deezer", "Add a Web App…"])
        let heading = sut.menu.items[5] // drawn: a section header can't show the "Experimental" badge
        #expect(heading.title == "Safari Web Apps")
        #expect(!heading.isEnabled)
        #expect((heading.view?.frame.height ?? 0) > 20) // the note under it too
        let row = sut.menu.items[6]
        #expect(row.isEnabled)
        #expect(row.subtitle == "Click to add") // as its tile says
        #expect(row.image?.isTemplate == true)
        try perform(row)
        #expect(log.calls == ["menuWillOpen", "player \(suggestion.bundleID)"])
    }

    @Test("a web app's controls are learned from the card's Controls row, learned or not; no other row offers it, and no steps show")
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
            prepareToOpen(sut)
            #expect(sut.model.status.canLearnControlsAgain) // the card shows its Controls row
            #expect(rows(sut.menu).prefix(2) == ["card", "snooze"]) // nothing else about learning
            sut.perform(.togglePlayerList)
            #expect(rows(sut.menu).prefix(8) == ["card", "supportedAppsHeading", "First", "otherAppsHeading", "Add an App…",
                                                 "webAppsHeading", "YT Music", "Add a Web App…"])
            sut.perform(.togglePlayerList)
        }

        // Its button: the menu closes, and a new learning window opens.
        sut.perform(.learnControls)
        await wait(for: 4, in: log)
        #expect(log.calls.suffix(1) == ["learnAgain"])

        // A player that learns nothing has no Controls row.
        status.chosenPlayerID = "com.example.first"
        status.learning = nil
        sut.status = status
        prepareToOpen(sut)
        #expect(!sut.model.status.canLearnControlsAgain)
    }

    @Test("an untested web app comes last, its name followed by an “Untested” badge")
    func untestedWebApp() {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        var untested = PlayerOption(bundleID: "com.apple.Safari.WebApp.U", name: "SoundCloud",
                                    appURL: URL(fileURLWithPath: "/Applications/SoundCloud.app"), kind: .safariWebApp)
        untested.isUntested = true
        status.playerOptions = [
            PlayerOption(bundleID: "com.example.first", name: "First", appURL: URL(fileURLWithPath: "/Applications/First.app")),
            untested,
            .suggestion(WebAppSuggestion(name: "Deezer", address: "deezer.com")),
        ]
        sut.status = status
        prepareToOpen(sut)
        sut.perform(.togglePlayerList)
        #expect(rows(sut.menu).prefix(8) == ["card", "supportedAppsHeading", "First", "otherAppsHeading", "Add an App…",
                                             "webAppsHeading", "Deezer", "SoundCloud"])
        let row = sut.menu.items[7]
        #expect(row.title == "SoundCloud")
        #expect(row.attributedTitle?.string.hasPrefix("SoundCloud") == true)
        #expect(row.attributedTitle?.containsAttachments(in: NSRange(location: 0, length: row.attributedTitle?.length ?? 0)) == true)
        #expect(sut.menu.items[6].attributedTitle == nil) // a tested one has no badge
        #expect(row.accessibilityLabel()?.contains("Safari web app") != true) // no app has its name
    }

    @Test("a web app named as an app is is read as a Safari web app, with its badge")
    func webAppNamedAsApp() {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        var untested = PlayerOption(bundleID: "com.apple.Safari.WebApp.M", name: "First",
                                    appURL: URL(fileURLWithPath: "/Applications/First Web.app"), kind: .safariWebApp)
        untested.isUntested = true
        status.playerOptions = [
            PlayerOption(bundleID: "com.example.first", name: "First", appURL: URL(fileURLWithPath: "/Applications/First.app")),
            untested,
        ]
        sut.status = status
        prepareToOpen(sut)
        sut.perform(.togglePlayerList)
        let rows = sut.menu.items.filter { $0.title == "First" }
        #expect(rows.count == 2)
        #expect(rows[0].accessibilityLabel()?.contains("Safari web app") != true)
        #expect(rows[1].accessibilityLabel() == "First, Safari web app, Untested")
    }

    @Test("a long untested name is cut short with “…”, so its badge still shows; its plain title stays whole")
    func longUntestedName() throws {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        let long = "A Music Service With A Very Long Name That Goes On And On Well Past The Menu's Edge"
        var untested = PlayerOption(bundleID: "com.apple.Safari.WebApp.L", name: long,
                                    appURL: URL(fileURLWithPath: "/Applications/Long.app"), kind: .safariWebApp)
        untested.isUntested = true
        status.playerOptions = [untested]
        sut.status = status
        prepareToOpen(sut)
        sut.perform(.togglePlayerList)
        let row = try #require(sut.menu.items.first { $0.title == long })
        let shown = row.attributedTitle?.string ?? ""
        #expect(shown.contains("…"))
        #expect(!shown.contains("Edge"))
        #expect(row.attributedTitle?.containsAttachments(in: NSRange(location: 0, length: row.attributedTitle?.length ?? 0)) == true)
        #expect(NSMenuItem.truncated("Short", toFit: 500, font: StatusMenuController.rowFont) == "Short")
    }

    @Test("from eight players on, a search comes first and narrows them down; fewer have none")
    func playerSearch() {
        let sut = makeController()
        defer { sut.remove() }
        let names = ["Spotify", "Apple Music", "VLC", "Apple Podcasts", "TIDAL", "Qobuz", "Deezer", "Música"]
        var status = readyStatus()
        status.playerOptions = names.map {
            PlayerOption(bundleID: "com.example.\($0)", name: $0, appURL: $0 == "Deezer" ? nil : URL(fileURLWithPath: "/Applications/\($0).app"))
        }
        sut.status = status
        prepareToOpen(sut)

        sut.perform(.togglePlayerList)
        #expect(rows(sut.menu).prefix(11) == ["card", "playerSearch", "supportedAppsHeading", "Spotify", "Apple Music", "VLC",
                                              "Apple Podcasts", "TIDAL", "Qobuz", "Música", "Deezer"])
        sut.perform(.searchPlayers("MUSI"))
        #expect(sut.model.playerSearch == "MUSI")
        #expect(rows(sut.menu).prefix(8) == ["card", "playerSearch", "supportedAppsHeading", "Apple Music", "Música", "Add an App…",
                                             "Add a Web App…", "snooze"])
        sut.perform(.searchPlayers("zz"))
        #expect(rows(sut.menu).prefix(6) == ["card", "playerSearch", "No players match “zz”.", "Add an App…", "Add a Web App…", "snooze"])
        #expect(sut.menu.items[2].isEnabled == false)
        sut.perform(.searchPlayers(""))
        #expect(rows(sut.menu).count(where: { names.contains($0) }) == 8)

        sut.perform(.togglePlayerList) // folded: the search goes, and what was typed with it
        #expect(rows(sut.menu).prefix(2) == ["card", "snooze"])
        #expect(sut.model.playerSearch.isEmpty)
        sut.perform(.searchPlayers("a")) // a closing field handing its text back changes nothing
        #expect(rows(sut.menu).prefix(2) == ["card", "snooze"])

        status.playerOptions.removeLast()
        sut.status = status
        prepareToOpen(sut)
        sut.perform(.togglePlayerList)
        #expect(rows(sut.menu).prefix(3) == ["card", "supportedAppsHeading", "Spotify"]) // seven: no search
    }

    @Test("More Settings sits below Ignored Apps, folded at first: its chevron shows Detection's, Fades' and Advanced's rows, each a row of its own, once the click is handled, and they stay as left when the menu opens again; only the rows that apply show, following the settings")
    func moreSettings() {
        let settingsModel = SettingsModel(settings: settings, updates: updates, actions: actions,
                                          launchAtLoginController: MockLaunchAtLoginController(isEnabled: false))
        let sut = StatusMenuController(settings: settings, session: session, updates: updates, actions: actions,
                                       settingsModel: settingsModel)
        defer { sut.remove() }
        var status = readyStatus()
        status.ignoredApps = [vlc]
        sut.status = status
        prepareToOpen(sut)
        #expect(rows(sut.menu).suffix(5) == ["Ignored Apps", "—", "moreSettings.chevron", "—", "toolbar"])
        #expect(!sut.model.showsMoreSettings)
        func settle() { RunLoop.main.run(until: Date() + 0.05) } // once the click is handled

        sut.model.perform(.toggleMoreSettings)
        settle()
        let shown = ["detection", "pauseAfter", "resumeAfter", "silenceThreshold", "fades", "fadeOut", "fadeIn",
                     "advanced", "staysPausedAfterCalls", "chevron"].map { "moreSettings.\($0)" }
        #expect(Array(rows(sut.menu).drop { $0 != "moreSettings.detection" }.prefix(shown.count)) == shown)
        #expect(sut.model.moreSettingsArrived == Set(MoreSettingsRow.allCases)) // every row's content shows
        prepareToOpen(sut)
        #expect(sut.model.showsMoreSettings) // kept, unlike the players' list

        // AntiDot mode: its ways instead of the silence threshold, and leveling dimmed.
        SettingsSwitch.antiDot.set(true, in: settingsModel)
        sut.model.perform(.updateMoreSettings) // as its chevron's row asks when they change
        settle()
        #expect(rows(sut.menu).contains("moreSettings.antiDotWays") && !rows(sut.menu).contains("moreSettings.silenceThreshold"))
        #expect(settings.state.detection == .playbackSignals && SettingsSwitch.levelsMusic.isUnavailable(settingsModel))
        // Fades off: their lengths go.
        SettingsSwitch.fades.set(false, in: settingsModel)
        sut.model.perform(.updateMoreSettings)
        settle()
        #expect(!rows(sut.menu).contains("moreSettings.fadeOut") && !rows(sut.menu).contains("moreSettings.fadeIn"))

        sut.model.perform(.toggleMoreSettings)
        settle()
        #expect(rows(sut.menu).suffix(5) == ["Ignored Apps", "—", "moreSettings.chevron", "—", "toolbar"])
    }

    @Test("the players are folded again each time the menu opens")
    func playerListFoldsOnOpening() {
        let sut = makeController()
        defer { sut.remove() }
        sut.status = readyStatus()
        prepareToOpen(sut)
        sut.perform(.togglePlayerList)
        prepareToOpen(sut)
        #expect(!sut.model.isChoosingPlayer)
        #expect(rows(sut.menu).prefix(2) == ["card", "snooze"])
    }

    // MARK: - Commands

    @Test("switches act at once and keep the menu open")
    func switches() {
        let sut = makeController()
        defer { sut.remove() }
        // As the menu's views send them.
        sut.model.perform(.toggleAutoPause)
        sut.model.perform(.setIgnored(chrome, true))
        #expect(settings.state.autoPause == .off)
        #expect(settings.state.ignoredApps.map(\.id) == [chrome.id])
        #expect(log.calls.isEmpty)
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

    @Test("no row has a keyboard shortcut, in any state")
    func noShortcuts() {
        let sut = makeController()
        defer { sut.remove() }
        func allItems(_ menu: NSMenu) -> [NSMenuItem] {
            menu.items.flatMap { [$0] + ($0.submenu.map(allItems) ?? []) }
        }
        let release = AppRelease(version: AppVersion("0.3.0")!, pageURL: URL(string: "https://example.com")!)
        // A failed start, an ignored app and an update found, every row showing.
        var failed = AppStatus()
        failed.choosePlayer(named: "Jukebox")
        failed.setHealth(.retrying("Jukebox isn’t responding"))
        failed.ignoredApps = [vlc]
        failed.updateOffer = UpdateOffer(release: release, state: .available)
        // Paused for apps playing and played, Audio Recording missing, an
        // app added through a check among the players, an update installing.
        var paused = readyStatus()
        paused.playerOptions.append(PlayerOption(bundleID: "com.example.checked", name: "Checked",
                                                 appURL: URL(fileURLWithPath: "/Applications/Checked.app"), kind: .checkedApp))
        paused.detection = .unavailable
        paused.setActiveSources([vlc, chrome])
        paused.setActiveSources([chrome])
        paused.updateOffer = UpdateOffer(release: release, state: .installing)
        for status in [failed, paused] {
            sut.status = status
            prepareToOpen(sut)
            sut.perform(.togglePlayerList)
            #expect(allItems(sut.menu).allSatisfy { $0.keyEquivalent.isEmpty })
        }
        sut.status = failed
        prepareToOpen(sut)
        #expect(!sut.menu.items.contains { $0.isHidden })
    }

    // MARK: - Rows

    @Test("ignored apps can be un-ignored from their own submenu")
    func ignoredAppsSubmenu() throws {
        let sut = makeController()
        defer { sut.remove() }
        settings.setIgnored(vlc, true)
        var status = readyStatus()
        status.ignoredApps = [vlc]
        sut.status = status
        prepareToOpen(sut)

        let submenu = try #require(try item("Ignored Apps", in: sut.menu).submenu)
        #expect(submenu.items.map(\.title) == ["Click an app to stop ignoring it", "VLC"])
        try perform(submenu.items[1])
        #expect(log.calls == ["menuWillOpen"])
        #expect(settings.state.ignoredApps.isEmpty)
    }

    @Test("Ignored Apps follows the switches while the menu is open: it shows, lists and goes")
    func ignoredAppsFollowWhileOpen() throws {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        status.setActiveSources([vlc, chrome])
        sut.status = status
        prepareToOpen(sut)
        sut.menuWillOpen(sut.menu)
        #expect(!rows(sut.menu).contains("Ignored Apps"))

        status.ignoredApps = [vlc]
        sut.status = status
        #expect(rows(sut.menu) == ["card", "snooze", "—", "playingApps", "—", "Ignored Apps", "—", "toolbar"])
        let submenu = try #require(try item("Ignored Apps", in: sut.menu).submenu)
        #expect(submenu.items.map(\.title) == ["Click an app to stop ignoring it", "VLC"])

        status.ignoredApps = [chrome, vlc]
        sut.status = status
        #expect(submenu.items.map(\.title) == ["Click an app to stop ignoring it", chrome.name, "VLC"])

        status.ignoredApps = []
        sut.status = status
        #expect(!rows(sut.menu).contains("Ignored Apps"))
        sut.menuDidClose(sut.menu)
    }

    @Test("once the user went to allow audio recording, its row reopens AutoHush")
    func reopenItem() throws {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        status.detection = .unavailable
        status.awaitsReopenForAudioRecording = true
        sut.status = status
        prepareToOpen(sut)

        #expect(rows(sut.menu).prefix(4) == ["card", "Reopen AutoHush", "Use AntiDot Mode Instead", "snooze"])
        try perform(try item("Reopen AutoHush", in: sut.menu))
        try perform(try item("Use AntiDot Mode Instead", in: sut.menu))
        #expect(log.calls == ["menuWillOpen", "reopen"])
        #expect(settings.state.detection == .playbackSignals)
    }

    @Test("a warning appears under the card as one actionable row")
    func warningItem() throws {
        let sut = makeController()
        defer { sut.remove() }
        var status = AppStatus()
        status.choosePlayer(named: "Jukebox")
        status.setHealth(.needsPermission(.automation(player: "Jukebox")))
        sut.status = status
        prepareToOpen(sut)

        #expect(rows(sut.menu).prefix(3) == ["card", "Allow Jukebox Automation Access…", "snooze"])
        try perform(try item("Allow Jukebox Automation Access…", in: sut.menu))
        #expect(log.calls == ["menuWillOpen", "warning Allow Jukebox Automation Access…"])
    }

    @Test("once an update is found, a row above the toolbar shows it, greyed out while it installs",
          arguments: [UpdateOffer.State.available, .downloaded])
    func updateItem(state: UpdateOffer.State) throws {
        let sut = makeController()
        defer { sut.remove() }
        let release = AppRelease(version: AppVersion("0.3.0")!, pageURL: URL(string: "https://example.com")!)
        var status = readyStatus()
        status.updateOffer = UpdateOffer(release: release, state: state)
        sut.status = status
        prepareToOpen(sut)
        #expect(rows(sut.menu).suffix(2) == ["Install AutoHush 0.3.0…", "toolbar"])
        let install = try item("Install AutoHush 0.3.0…", in: sut.menu)
        #expect(install.image != nil)
        try perform(install)
        #expect(log.calls == ["menuWillOpen", "update"])

        status.updateOffer = UpdateOffer(release: release, state: .installing)
        sut.status = status
        prepareToOpen(sut)
        let installing = try item("Installing AutoHush 0.3.0…", in: sut.menu)
        #expect(installing.action == nil)
        #expect(!installing.isEnabled)
    }
}
