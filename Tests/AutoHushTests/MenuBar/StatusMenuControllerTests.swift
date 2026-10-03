import AppKit
import Testing
@testable import AutoHush

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
            setIgnored: { log.calls.append("ignore \($0.id) \($1)") },
            resolveWarning: { log.calls.append("warning \($0.title)") },
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

    @Test("the initial menu shows the status, auto-pause controls, Settings and Quit")
    func initialMenu() throws {
        let sut = makeController()
        defer { sut.remove() }

        #expect(sut.statusItem.button?.image != nil)
        #expect(sut.menu.items.first?.title == "Starting services")
        #expect(sut.menu.items.first?.isEnabled == false)
        #expect(try item("Auto-Pause Music", in: sut.menu).state == .on)
        #expect(try item("Turn Off For", in: sut.menu).submenu?.items.map(\.title)
            == ["15 Minutes", "1 Hour", "Until Tomorrow"])
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

    @Test("auto-pause off is unchecked and dims the icon")
    func autoPauseOff() throws {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        status.autoPause = .snoozed(until: "15:30")
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
        try perform(try #require(try item("Turn Off For", in: sut.menu).submenu?.items[1]))
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

    @Test("an available update adds an item that opens it")
    func updateAvailableItem() throws {
        let log = ActionLog()
        let sut = makeController(log)
        defer { sut.remove() }
        #expect(!sut.menu.items.contains { $0.title.hasPrefix("Update Available") })

        var status = readyStatus()
        status.availableUpdate = AppRelease(version: AppVersion("0.3.0")!, pageURL: URL(string: "https://example.com")!)
        sut.status = status
        try perform(try item("Update Available: 0.3.0…", in: sut.menu))
        #expect(log.calls == ["update"])
    }
}
