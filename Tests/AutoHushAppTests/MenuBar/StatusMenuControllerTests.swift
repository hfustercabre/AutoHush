import AppKit
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("StatusMenuController")
@MainActor
struct StatusMenuControllerTests {
    private final class ActionLog {
        var calls: [String] = []
    }

    private let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome")
    private let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC")

    private func makeController(_ log: ActionLog = ActionLog()) -> StatusMenuController {
        StatusMenuController(actions: .init(
            toggleAutoPause: { log.calls.append("toggleAutoPause") },
            snooze: { log.calls.append("snooze \($0.title)") },
            chooseMusicPlayer: { log.calls.append("player \($0)") },
            menuWillOpen: { log.calls.append("menuWillOpen") },
            setIgnored: { log.calls.append("ignore \($0.id) \($1)") },
            resolveWarning: { log.calls.append("warning \($0.grantTitle)") },
            retry: { log.calls.append("retry") },
            openSettings: { log.calls.append("settings") },
            showDiagnostics: { log.calls.append("diagnostics") },
            showAvailableUpdate: { log.calls.append("update") },
            checkForUpdates: { log.calls.append("checkUpdates") },
            showAbout: { log.calls.append("about") },
            quit: { log.calls.append("quit") }
        ))
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
    private func wait(for count: Int, in log: ActionLog) async {
        for _ in 0..<200 where log.calls.count < count { try? await Task.sleep(for: .milliseconds(5)) }
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

    @Test("the views follow the status at once; rows are added only when the menu next opens")
    func rowsWaitForTheNextOpening() {
        let sut = makeController()
        defer { sut.remove() }
        sut.status = readyStatus()
        prepareToOpen(sut)
        sut.menuWillOpen(sut.menu)

        var status = readyStatus()
        status.setActiveSources([chrome])
        sut.status = status
        #expect(sut.model.status == status)           // the card shows it
        #expect(sut.model.listedSources.isEmpty)      // no row moves under the pointer
        #expect(!rows(sut.menu).contains("playingApps"))

        sut.menuDidClose(sut.menu)
        #expect(!sut.isMenuOpen)
        prepareToOpen(sut)
        #expect(rows(sut.menu).contains("playingApps"))
    }

    @Test("the app can bring the status up to date before the menu opens")
    func updateBeforeOpening() {
        let log = ActionLog()
        let sut = makeController(log)
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
        #expect(sut.model.status.statusLine == "Auto-pause is off until 15:30")
    }

    // MARK: - The music player

    @Test("the player button unfolds the players under the card; one that isn't installed comes last and can't be chosen")
    func playerList() throws {
        let log = ActionLog()
        let sut = makeController(log)
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
        #expect(rows(sut.menu).prefix(5) == ["card", "First", "Third", "Second", "snooze"])
        let players = Array(sut.menu.items[1...3])
        #expect(players.map(\.state) == [.on, .off, .off])
        #expect(players.map(\.isEnabled) == [true, true, false])
        #expect(players.map(\.subtitle) == [nil, nil, "Not installed"])
        #expect(players.allSatisfy { $0.image != nil })
        try perform(players[1])
        #expect(log.calls == ["menuWillOpen", "player com.example.third"])

        sut.perform(.togglePlayerList)
        #expect(!sut.model.isChoosingPlayer)
        #expect(rows(sut.menu).prefix(2) == ["card", "snooze"])
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
        #expect(rows(sut.menu).prefix(10) == ["card", "playerSearch", "Spotify", "Apple Music", "VLC", "Apple Podcasts",
                                              "TIDAL", "Qobuz", "Música", "Deezer"])
        sut.perform(.searchPlayers("MUSI"))
        #expect(sut.model.playerSearch == "MUSI")
        #expect(rows(sut.menu).prefix(5) == ["card", "playerSearch", "Apple Music", "Música", "snooze"])
        sut.perform(.searchPlayers("zz"))
        #expect(rows(sut.menu).prefix(4) == ["card", "playerSearch", "No players match “zz”.", "snooze"])
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
        #expect(rows(sut.menu).prefix(2) == ["card", "Spotify"]) // seven: no search
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
        let log = ActionLog()
        let sut = makeController(log)
        defer { sut.remove() }
        sut.perform(.toggleAutoPause)
        sut.perform(.setIgnored(chrome, true))
        #expect(log.calls == ["toggleAutoPause", "ignore com.google.Chrome true"])
    }

    @Test("buttons close the menu, then act")
    func buttons() async {
        let log = ActionLog()
        let sut = makeController(log)
        defer { sut.remove() }
        let commands: [StatusMenuCommand] = [.snooze(.oneHour), .openSettings, .showDiagnostics, .updates, .showAbout, .quit]
        commands.forEach(sut.perform)
        #expect(log.calls.isEmpty) // not yet: the menu closes first
        await wait(for: commands.count, in: log)
        #expect(log.calls == ["snooze 1 Hour", "settings", "diagnostics", "checkUpdates", "about", "quit"])
    }

    @Test("once an update is found, Updates shows it instead of checking again")
    func updatesShowsTheOffer() async {
        let log = ActionLog()
        let sut = makeController(log)
        defer { sut.remove() }
        var status = readyStatus()
        let release = AppRelease(version: AppVersion("0.3.0")!, pageURL: URL(string: "https://example.com")!)
        status.updateOffer = UpdateOffer(release: release, state: .available)
        sut.status = status
        sut.perform(.updates)
        await wait(for: 1, in: log)
        #expect(log.calls == ["update"])
    }

    @Test("Retry tries again at once and keeps the menu open")
    func retry() {
        let log = ActionLog()
        let sut = makeController(log)
        defer { sut.remove() }
        sut.perform(.retry)
        #expect(log.calls == ["retry"])
    }

    @Test("no row has a keyboard shortcut, in any state")
    func noShortcuts() {
        let sut = makeController()
        defer { sut.remove() }
        var status = AppStatus()
        status.choosePlayer(named: "Jukebox")
        status.setHealth(.retrying("Jukebox is not responding"))
        status.ignoredApps = [vlc]
        let release = AppRelease(version: AppVersion("0.3.0")!, pageURL: URL(string: "https://example.com")!)
        status.updateOffer = UpdateOffer(release: release, state: .available)
        sut.status = status
        prepareToOpen(sut)
        sut.perform(.togglePlayerList)

        func allItems(_ menu: NSMenu) -> [NSMenuItem] {
            menu.items.flatMap { [$0] + ($0.submenu.map(allItems) ?? []) }
        }
        #expect(allItems(sut.menu).allSatisfy { $0.keyEquivalent.isEmpty })
        #expect(!sut.menu.items.contains { $0.isHidden })
    }

    // MARK: - Rows

    @Test("ignored apps can be un-ignored from their own submenu")
    func ignoredAppsSubmenu() throws {
        let log = ActionLog()
        let sut = makeController(log)
        defer { sut.remove() }
        var status = readyStatus()
        status.ignoredApps = [vlc]
        sut.status = status
        prepareToOpen(sut)

        let submenu = try #require(try item("Ignored Apps", in: sut.menu).submenu)
        #expect(submenu.items.map(\.title) == ["Click an app to stop ignoring it", "VLC"])
        try perform(submenu.items[1])
        #expect(log.calls == ["menuWillOpen", "ignore org.videolan.vlc false"])
    }

    @Test("a warning appears under the card as one actionable row")
    func warningItem() throws {
        let log = ActionLog()
        let sut = makeController(log)
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
        let log = ActionLog()
        let sut = makeController(log)
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
