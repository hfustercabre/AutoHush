import AppKit
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushPlayers
import SpotifySupport
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

    private func readyStatus() -> AppStatus {
        var status = AppStatus()
        status.setHealth(.ready)
        status.playback = .pausedByMonitor
        return status
    }

    private func item(_ title: String, in menu: NSMenu) throws -> NSMenuItem {
        try #require(menu.items.first { $0.title == title }, "no menu item \"\(title)\"")
    }

    private func perform(_ item: NSMenuItem) throws {
        let menu = try #require(item.menu)
        menu.performActionForItem(at: menu.index(of: item))
    }

    @Test("the menu is rebuilt only when the status changes")
    func rebuildsOnlyOnChange() throws {
        let sut = makeController()
        defer { sut.remove() }
        sut.status = readyStatus()
        let first = try #require(sut.menu.items.first)

        sut.status = readyStatus() // the same again
        #expect(sut.menu.items.first === first)

        var changed = readyStatus()
        changed.playback = .musicPlaying
        sut.status = changed
        #expect(sut.menu.items.first !== first)
        #expect(sut.menu.items.first?.title == "Music is playing")
    }

    @Test("the initial menu shows the status, auto-pause controls, Settings and Quit")
    func initialMenu() throws {
        let sut = makeController()
        defer { sut.remove() }

        #expect(sut.statusItem.button?.image != nil)
        #expect(sut.menu.items.first?.title == "Starting services")
        #expect(sut.menu.items.first?.isEnabled == false)
        #expect(try item("Auto-Pause Music", in: sut.menu).state == .on)
        #expect(try item("Turn Off For", in: sut.menu).submenu?.items.map(\.title)
            == ["5 Minutes", "15 Minutes", "30 Minutes", "1 Hour", "24 Hours"])
        #expect(sut.menu.items.contains { $0.title == "Music Player" })
        #expect(sut.menu.items.contains { $0.title == "Settings…" })
        #expect(sut.menu.items.contains { $0.title == "Quit AutoHush" })
        #expect(!sut.menu.items.contains { $0.title == "Retry" || $0.title == "Ignored Apps" })
    }

    @Test("while the menu is open only the status line changes; the rest updates when it closes")
    func deferredRebuildWhileOpen() throws {
        let sut = makeController()
        defer { sut.remove() }
        sut.status = readyStatus()
        let itemCount = sut.menu.items.count

        sut.menuWillOpen(sut.menu)
        var status = readyStatus()
        status.setActiveSources([chrome])
        sut.status = status
        #expect(sut.menu.items.count == itemCount)          // no rows added under the pointer
        #expect(sut.menu.items.first?.title == status.statusLine)

        sut.menuDidClose(sut.menu)
        _ = try item("Google Chrome", in: sut.menu)         // rebuilt once closed
        #expect(!sut.isMenuOpen)
    }

    @Test("each playing app gets a row with its ignore toggle")
    func sourceRows() throws {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        status.ignoredApps = [vlc]
        status.setActiveSources([vlc, chrome])
        sut.status = status

        let chromeRow = try item("Google Chrome", in: sut.menu)
        #expect(chromeRow.image != nil)
        #expect(chromeRow.subtitle == nil)
        #expect(chromeRow.submenu?.items.first?.title == "Never Pause Music for Google Chrome")
        #expect(chromeRow.submenu?.items.first?.state == .off)

        let vlcRow = try item("VLC", in: sut.menu)
        #expect(vlcRow.subtitle == "Ignored — music keeps playing")
        #expect(vlcRow.submenu?.items.first?.state == .on)
    }

    @Test("ignored apps can be un-ignored from their own submenu")
    func ignoredAppsSubmenu() throws {
        let log = ActionLog()
        let sut = makeController(log)
        defer { sut.remove() }
        var status = readyStatus()
        status.ignoredApps = [vlc]
        sut.status = status

        let submenu = try #require(try item("Ignored Apps", in: sut.menu).submenu)
        #expect(submenu.items.map(\.title) == ["Click an app to stop ignoring it", "VLC"])
        try perform(submenu.items[1])
        #expect(log.calls == ["ignore org.videolan.vlc false"])
    }

    @Test("the music player is chosen from its own submenu; one that isn't installed can't be")
    func musicPlayerSubmenu() throws {
        let log = ActionLog()
        let sut = makeController(log)
        defer { sut.remove() }
        var status = readyStatus()
        status.playerOptions = [
            PlayerOption(bundleID: "com.example.first", name: "First", appURL: URL(fileURLWithPath: "/Applications/First.app")),
            PlayerOption(bundleID: "com.example.second", name: "Second", appURL: URL(fileURLWithPath: "/Applications/Second.app")),
            PlayerOption(bundleID: "com.example.third", name: "Third", appURL: nil),
        ]
        status.chosenPlayerID = "com.example.first"
        sut.status = status

        let submenu = try #require(try item("Music Player", in: sut.menu).submenu)
        #expect(submenu.items.map(\.title) == ["First", "Second", "Third"])
        #expect(submenu.items.map(\.state) == [.on, .off, .off])
        #expect(submenu.items.map(\.isEnabled) == [true, true, false])
        #expect(submenu.items.map(\.subtitle) == [nil, nil, "Not installed"])
        #expect(submenu.items.allSatisfy { $0.image != nil })
        try perform(submenu.items[1])
        #expect(log.calls == ["player com.example.second"])
    }

    @Test("the app can bring the status up to date before the menu opens")
    func updateBeforeOpening() {
        let log = ActionLog()
        let sut = makeController(log)
        defer { sut.remove() }
        sut.menuNeedsUpdate(sut.menu)
        #expect(log.calls == ["menuWillOpen"])
    }

    @Test("auto-pause off is unchecked and dims the icon")
    func autoPauseOff() throws {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        status.autoPause = .snoozed("until 15:30")
        sut.status = status

        #expect(try item("Auto-Pause Music", in: sut.menu).state == .off)
        #expect(sut.menu.items.first?.title == "Auto-pause is off until 15:30")
        #expect(sut.statusItem.button?.appearsDisabled == true)
    }

    @Test("a warning appears as one actionable item, with Retry when needed")
    func warningItem() throws {
        let log = ActionLog()
        let sut = makeController(log)
        defer { sut.remove() }
        var status = AppStatus()
        status.playerName = "Spotify"
        status.setHealth(.needsPermission("Grant Automation access"))
        sut.status = status

        try perform(try item("Allow Spotify Automation Access…", in: sut.menu))
        try perform(try item("Retry", in: sut.menu))
        #expect(log.calls == ["warning Allow Spotify Automation Access…", "retry"])
    }

    @Test("Diagnostics is the Option alternate of Settings")
    func diagnosticsAlternate() throws {
        let sut = makeController()
        defer { sut.remove() }
        let settings = try item("Settings…", in: sut.menu)
        let diagnostics = try item("Diagnostics…", in: sut.menu)
        #expect(diagnostics.isAlternate)
        #expect(diagnostics.keyEquivalent == settings.keyEquivalent)
        #expect(diagnostics.keyEquivalentModifierMask == [.command, .option])
        #expect(sut.menu.index(of: diagnostics) == sut.menu.index(of: settings) + 1)
    }

    @Test("menu actions reach their handlers")
    func actionsReachHandlers() throws {
        let log = ActionLog()
        let sut = makeController(log)
        defer { sut.remove() }
        var status = readyStatus()
        status.setActiveSources([chrome])
        sut.status = status

        try perform(try item("Auto-Pause Music", in: sut.menu))
        try perform(try #require(try item("Turn Off For", in: sut.menu).submenu?.items[3]))
        try perform(try #require(try item("Google Chrome", in: sut.menu).submenu?.items.first))
        try perform(try item("Settings…", in: sut.menu))
        try perform(try item("Diagnostics…", in: sut.menu))
        try perform(try item("About AutoHush", in: sut.menu))
        try perform(try item("Check for Updates…", in: sut.menu))
        try perform(try item("Quit AutoHush", in: sut.menu))
        #expect(log.calls == [
            "toggleAutoPause", "snooze 1 Hour", "ignore com.google.Chrome true",
            "settings", "diagnostics", "about", "checkUpdates", "quit",
        ])
    }

    @Test("once an update is found, Check for Updates becomes an item that shows it, greyed out while it installs",
          arguments: [UpdateOffer.State.available, .downloaded])
    func updateItem(state: UpdateOffer.State) throws {
        let log = ActionLog()
        let sut = makeController(log)
        defer { sut.remove() }
        #expect(sut.menu.items.contains { $0.title == "Check for Updates…" })

        let release = AppRelease(version: AppVersion("0.3.0")!, pageURL: URL(string: "https://example.com")!)
        var status = readyStatus()
        status.updateOffer = UpdateOffer(release: release, state: state)
        sut.status = status
        #expect(!sut.menu.items.contains { $0.title == "Check for Updates…" })
        let install = try item("Install AutoHush 0.3.0…", in: sut.menu)
        #expect(install.image != nil)
        try perform(install)
        #expect(log.calls == ["update"])

        status.updateOffer = UpdateOffer(release: release, state: .installing)
        sut.status = status
        let installing = try item("Installing AutoHush 0.3.0…", in: sut.menu)
        #expect(installing.action == nil)
        #expect(!installing.isEnabled)
    }
}
