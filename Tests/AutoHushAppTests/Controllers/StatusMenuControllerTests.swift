import AppKit
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

/// Each test has its own menu bar item and notification centers (another
/// desktop, another window becoming key): they run at once.
@Suite("StatusMenuController", .waitsTimeLimit)
@MainActor
struct StatusMenuControllerTests {
    let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome")
    let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC")
    /// What the menu asked of AppDelegate and the updates, in order; the
    /// user's settings and the player session show their own changes.
    let log = CallLog()
    let actions: FakeAppActions
    let updates: FakeUpdateCommands
    let settings = UserSettings.inMemory()
    private let session = PlayerSession.noPlayer()
    /// The First player, installed.
    static let first = PlayerOption(bundleID: TestPlayers.first, name: "First", appURL: URL(fileURLWithPath: "/Applications/First.app"))

    init() {
        actions = FakeAppActions(log: log)
        updates = FakeUpdateCommands(log: log)
    }

    /// The menu's own notification centers: no other test's windows or
    /// desktops reach it, and its notifications reach no other menu.
    let center = NotificationCenter()
    let workspaceCenter = NotificationCenter()

    /// A menu whose timing waits only a turn (the tests await its tasks),
    /// with Reduce Motion off.
    func makeController(settingsModel: SettingsModel? = nil) -> StatusMenuController {
        let sut = StatusMenuController(settings: settings, session: session, updates: updates, actions: actions, settingsModel: settingsModel)
        sut.notificationCenter = center
        sut.workspaceCenter = workspaceCenter
        sut.reducesMotion = { false }
        sut.pause = { _ in await Task.yield() }
        return sut
    }

    /// Ready to control the Jukebox player, paused for another app.
    func readyStatus() -> AppStatus {
        var status = AppStatus()
        status.choosePlayer(named: "Jukebox")
        status.setHealth(.ready)
        status.playback = .pausedByMonitor
        return status
    }

    /// The menu opens anew, put together for the status (its panel not shown).
    func reopen(_ sut: StatusMenuController) {
        sut.close()
        sut.open(showsPanel: false)
    }

    /// The menu's parts, in order: a warning by its row's title.
    func parts(_ sut: StatusMenuController) -> [String] {
        sut.model.sections.map { section in
            switch section {
            case .card: "card"
            case .warning(let permission): permission.grantTitle
            case .reopenAutoHush: PermissionText.reopen
            case .useAntiDot: PermissionText.useAntiDot
            case .snooze: "snooze"
            case .playingNow: "playingNow"
            case .recentlyPlayed: "recentlyPlayed"
            case .ignoredApps: "ignoredApps"
            case .update: "update"
            case .toolbar: "toolbar"
            case .playerRow: "playerRow"
            }
        }
    }

    /// The unfolded players, by their groups: "[Supported]", "[Other]",
    /// "[Web]" over their names, and a note when the search matched none.
    func playerRows(_ sut: StatusMenuController) -> [String] {
        let list = sut.model.players
        var rows: [String] = list.showsSearch ? ["search"] : []
        if let note = list.noMatchNote { rows.append(note) }
        if !list.supportedApps.isEmpty { rows += ["[Supported]"] + list.supportedApps.map(\.option.name) }
        if list.showsOtherApps { rows += ["[Other]"] + list.otherApps.map(\.option.name) }
        if !list.webApps.isEmpty { rows += ["[Web]"] + list.webApps.map(\.option.name) }
        return rows
    }

    func row(_ name: String, in sut: StatusMenuController) throws -> MenuPlayerList.Row {
        let list = sut.model.players
        return try #require((list.supportedApps + list.otherApps + list.webApps).first { $0.option.name == name }, "no player \"\(name)\"")
    }

    /// Waits until `log` has `count` calls: some commands run once the menu
    /// has closed.
    func wait(for count: Int, in log: CallLog, sourceLocation: SourceLocation = #_sourceLocation) async {
        await TestWait.until(sourceLocation: sourceLocation) { log.calls.count >= count }
    }

    // MARK: - Layout

    @Test("the menu is the card (Change Player at its foot), the duration buttons, Ignored Apps and the toolbar; playing apps add their part, Settings' model none (the settings are Settings' only)")
    func layout() {
        let sut = makeController()
        defer { sut.remove() }
        sut.status = readyStatus()
        reopen(sut)
        #expect(parts(sut) == ["card", "snooze", "ignoredApps", "toolbar"])

        var status = readyStatus()
        status.ignoredApps = [vlc]
        status.setActiveSources([vlc, chrome])
        sut.status = status
        reopen(sut)
        #expect(parts(sut) == ["card", "snooze", "playingNow", "ignoredApps", "toolbar"])
        #expect(sut.model.listedSources == [chrome, vlc])

        let withSettings = makeController(settingsModel: SettingsModel.forTests(actions: actions, updates: updates, settings: settings))
        defer { withSettings.remove() }
        withSettings.status = readyStatus()
        reopen(withSettings)
        #expect(parts(withSettings) == ["card", "snooze", "ignoredApps", "toolbar"])
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
        #expect(parts(sut) == ["card", "snooze", "playingNow", "recentlyPlayed", "ignoredApps", "toolbar"])
        #expect(sut.model.listedRecentSources == [vlc])

        status.setActiveSources([])
        sut.status = status
        reopen(sut)
        #expect(parts(sut) == ["card", "snooze", "recentlyPlayed", "ignoredApps", "toolbar"])
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

        sut.close()
        #expect(!sut.isMenuOpen)
        sut.close() // closed already: nothing
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

    @Test("Settings → General's hidden-icon note is read again each time the item's window moves, as when macOS places a new item (U8)")
    func itemMoveReadsHiddenIconAgain() throws {
        let settingsModel = SettingsModel.forTests(actions: actions, updates: updates, settings: settings)
        let sut = makeController(settingsModel: settingsModel)
        defer { sut.remove() }
        sut.followItemMoves()
        let window = try #require(sut.statusItem.button?.window)
        actions.menuBarIconIsHidden = true // placed behind the notch
        #expect(!settingsModel.menuBarIconHidden) // not read yet
        center.post(name: NSWindow.didMoveNotification, object: window)
        #expect(settingsModel.menuBarIconHidden)
        actions.menuBarIconIsHidden = false // ⌘-dragged out
        center.post(name: NSWindow.didMoveNotification, object: window)
        #expect(!settingsModel.menuBarIconHidden)
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
}
