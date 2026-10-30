import AppKit
import Testing
@testable import AutoHushApp
import AutoHushKit

extension StatusMenuControllerTests {
    // MARK: - The music player

    /// The menu open, First chosen among three players, Second not installed.
    private func menuWithPlayers() -> StatusMenuController {
        let sut = makeController()
        var status = readyStatus()
        status.playerOptions = [
            Self.first,
            PlayerOption(bundleID: TestPlayers.second, name: "Second", appURL: nil),
            PlayerOption(bundleID: "com.example.third", name: "Third", appURL: URL(fileURLWithPath: "/Applications/Third.app")),
        ]
        status.chosenPlayerID = TestPlayers.first
        sut.status = status
        reopen(sut)
        return sut
    }

    @Test("the Media Player row opens the players beside the menu, under “Supported Apps”, the chosen one checked; one that isn't installed comes last")
    func playerList() {
        let sut = menuWithPlayers()
        defer { sut.remove() }
        sut.perform(.openSide(.players))
        #expect(sut.model.isChoosingPlayer)
        #expect(playerRows(sut) == ["[Supported]", "First", "Third", "Second", "[Other]"])
        #expect(sut.model.players.supportedApps.map(\.isChosen) == [true, false, false])
    }

    @Test("a player that isn't installed can't be chosen in the menu, which says so")
    func uninstalledPlayer() {
        let sut = menuWithPlayers()
        defer { sut.remove() }
        sut.perform(.openSide(.players))
        let players = sut.model.players.supportedApps
        #expect(players.map(\.isEnabled) == [true, true, false])
        #expect(players.map(\.subtitle) == [nil, nil, "Not installed"])
    }

    @Test("choosing a player in the menu closes the players and keeps the menu open")
    func playerChosenInPlace() async {
        let sut = menuWithPlayers()
        defer { sut.remove() }
        sut.perform(.openSide(.players))
        // Chosen in place (the user, 2026-10-18): the menu stays open, the list folds.
        sut.perform(.choosePlayer("com.example.third"))
        #expect(sut.isMenuOpen && !sut.model.isChoosingPlayer)
        await wait(for: 2, in: log)
        #expect(log.calls == ["menuWillOpen", "player com.example.third"])
    }

    @Test("another of AutoHush's windows coming forward closes the menu, as a menu; a hidden one becoming key doesn't")
    func windowInFrontClosesMenu() {
        let sut = menuWithPlayers()
        defer { sut.remove() }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40), styleMask: .titled, backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        center.post(name: NSWindow.didBecomeKeyNotification, object: window)
        #expect(sut.isMenuOpen) // hidden
        window.orderFrontRegardless()
        center.post(name: NSWindow.didBecomeKeyNotification, object: window)
        #expect(!sut.isMenuOpen)
    }

    @Test("a window becoming key closes the menu unless it's the menu bar item's own (as VoiceOver's press on a row makes it) or at the menu bar's level")
    func windowsThatLeaveTheMenu() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40), styleMask: .titled, backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        window.orderFrontRegardless()
        #expect(!StatusMenuController.closesMenu(becomingKey: window, statusItemWindow: window))
        #expect(StatusMenuController.closesMenu(becomingKey: window, statusItemWindow: nil))
        window.level = .statusBar
        #expect(!StatusMenuController.closesMenu(becomingKey: window, statusItemWindow: nil))
    }

    @Test("the players fold again each time the menu opens")
    func playersFoldAsTheMenuOpens() {
        let sut = menuWithPlayers()
        defer { sut.remove() }
        sut.perform(.openSide(.players))
        reopen(sut)
        #expect(!sut.model.isChoosingPlayer) // closed again each time it opens
    }

    @Test("an app added through a check is offered under Other Apps, removable with Option held; Add an App… and Add a Web App… open their windows")
    func checkedApp() async throws {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        status.playerOptions = [
            Self.first,
            PlayerOption(bundleID: "com.example.checked", name: "Checked", appURL: URL(fileURLWithPath: "/Applications/Checked.app"),
                         kind: .checkedApp),
        ]
        status.chosenPlayerID = TestPlayers.first
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

    /// The players open in the menu: First, and two apps added through a
    /// check: Gone, chosen and no longer installed, and a Chromium browser's
    /// web app, Sounds.
    private func menuWithCheckedApps() -> StatusMenuController {
        let sut = makeController()
        var status = readyStatus()
        var chromeApp = PlayerOption(bundleID: "com.google.Chrome.app.sc", name: "Sounds",
                                     appURL: URL(fileURLWithPath: "/Users/test/Applications/Chrome Apps.localized/Sounds.app"),
                                     kind: .checkedApp)
        chromeApp.browserName = "Google Chrome"
        status.playerOptions = [
            Self.first,
            PlayerOption(bundleID: "com.example.gone", name: "Gone", appURL: nil, kind: .checkedApp),
            chromeApp,
        ]
        status.chosenPlayerID = "com.example.gone"
        sut.status = status
        reopen(sut)
        sut.perform(.openSide(.players))
        return sut
    }

    @Test("an app added through a check that isn't installed now stays under Other Apps, last, dimmed and “Not installed”")
    func uninstalledCheckedApp() throws {
        let sut = menuWithCheckedApps()
        defer { sut.remove() }
        #expect(playerRows(sut) == ["[Supported]", "First", "[Other]", "Sounds", "Gone"])
        let gone = try row("Gone", in: sut)
        #expect(!gone.isEnabled && gone.isChosen)
        #expect(gone.subtitle == "Not installed")
    }

    @Test("a Chromium browser's web app added through a check says whose it is")
    func browserAppRow() throws {
        let sut = menuWithCheckedApps()
        defer { sut.remove() }
        let sounds = try row("Sounds", in: sut)
        #expect(sounds.isEnabled)
        #expect(sounds.accessibilityLabel == "Sounds, Google Chrome web app")
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
            Self.first,
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
        let suggestion = PlayerOption.suggestion(WebAppSuggestion(name: "Discs", address: "discs.example"))
        status.playerOptions = [
            Self.first,
            suggestion,
        ]
        status.chosenPlayerID = TestPlayers.first
        sut.status = status
        reopen(sut)

        sut.perform(.openSide(.players))
        #expect(playerRows(sut) == ["[Supported]", "First", "[Other]", "[Web]", "Discs"])
        let discs = try row("Discs", in: sut)
        #expect(discs.isEnabled)
        #expect(discs.subtitle == "Click to add") // as its tile says
    }

    @Test("a web app's controls are learned from the card's Controls row; nothing else in the menu is about learning")
    func learnControls() async throws {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        let webApp = PlayerOption(bundleID: "com.apple.Safari.WebApp.TEST", name: "Yodel Music",
                                  appURL: URL(fileURLWithPath: "/Applications/Safari.app"), kind: .safariWebApp)
        status.playerOptions = [
            Self.first,
            webApp,
        ]
        status.chosenPlayerID = webApp.bundleID
        for learning in [LearningStatus.learned, .learning(hasPlayed: false), .learning(hasPlayed: true)] {
            status.learning = learning
            sut.status = status
            reopen(sut)
            #expect(sut.model.status.canLearnControlsAgain) // the card shows its Controls row
            #expect(parts(sut) == ["card", "snooze", "ignoredApps", "toolbar"])
        }

        // Its button: the menu closes, and a new learning window opens.
        sut.perform(.learnControls)
        await wait(for: 4, in: log)
        #expect(log.calls.suffix(1) == ["learnAgain"])

        // A player that learns nothing has no Controls row.
        status.chosenPlayerID = TestPlayers.first
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
        var untested = PlayerOption(bundleID: "com.apple.Safari.WebApp.U", name: "Sounds",
                                    appURL: URL(fileURLWithPath: "/Applications/Sounds.app"), kind: .safariWebApp)
        untested.isUntested = true
        var named = PlayerOption(bundleID: "com.apple.Safari.WebApp.M", name: "First",
                                 appURL: URL(fileURLWithPath: "/Applications/First Web.app"), kind: .safariWebApp)
        named.isUntested = true
        status.playerOptions = [
            Self.first,
            untested,
            named,
            .suggestion(WebAppSuggestion(name: "Discs", address: "discs.example")),
        ]
        sut.status = status
        reopen(sut)
        sut.perform(.openSide(.players))
        let web = sut.model.players.webApps
        #expect(web.map(\.option.name) == ["Discs", "Sounds", "First"])
        #expect(web[1].accessibilityLabel == "Sounds, Untested")
        #expect(web[2].accessibilityLabel == "First, Safari web app, Untested")
        #expect(sut.model.players.supportedApps[0].accessibilityLabel == "First")
    }

    /// The menu open with the first `count` of eight players, Discs not
    /// installed, their list open beside it.
    private func menuWithManyPlayers(_ count: Int = 8) -> StatusMenuController {
        let sut = makeController()
        let names = ["Streamer", "Acme Music", "Viewer", "Acme Podcasts", "Tides", "Quartet", "Discs", "Música"].prefix(count)
        var status = readyStatus()
        status.playerOptions = names.map {
            PlayerOption(bundleID: "com.example.\($0)", name: $0, appURL: $0 == "Discs" ? nil : URL(fileURLWithPath: "/Applications/\($0).app"))
        }
        sut.status = status
        reopen(sut)
        sut.perform(.openSide(.players))
        return sut
    }

    @Test("from eight players on, a search comes first among them")
    func playerSearch() {
        let sut = menuWithManyPlayers()
        defer { sut.remove() }
        #expect(playerRows(sut).prefix(10) == ["search", "[Supported]", "Streamer", "Acme Music", "Viewer", "Acme Podcasts", "Tides",
                                               "Quartet", "Música", "Discs"])
    }

    @Test("the players' search narrows them down, or says none match")
    func playerSearchNarrows() {
        let sut = menuWithManyPlayers()
        defer { sut.remove() }
        sut.perform(.searchPlayers("MUSI"))
        #expect(sut.model.playerSearch == "MUSI")
        #expect(playerRows(sut) == ["search", "[Supported]", "Acme Music", "Música"])
        sut.perform(.searchPlayers("zz"))
        #expect(playerRows(sut) == ["search", "No players match “zz”."])
    }

    @Test("Return with nothing highlighted chooses the first player the search left, only while something is typed")
    func playerSearchReturn() async {
        let sut = menuWithManyPlayers()
        defer { sut.remove() }
        sut.perform(.searchPlayers(""))
        sut.perform(.chooseHighlighted) // nothing typed: nothing chosen
        #expect(sut.model.isChoosingPlayer)
        sut.perform(.searchPlayers("music"))
        sut.perform(.chooseHighlighted)
        await wait(for: 2, in: log)
        #expect(log.calls == ["menuWillOpen", "player com.example.Acme Music"])
    }

    @Test("among the players, Space presses the highlighted one, not typing, until something is typed; then it's a space in the search")
    func spaceAmongPlayers() throws {
        let sut = menuWithManyPlayers()
        defer { sut.remove() }
        let space = try Self.keyDown(" ", code: 49)
        #expect(sut.handleKey(space))
        #expect(sut.model.playerSearch.isEmpty)
        sut.perform(.searchPlayers("apple"))
        #expect(sut.handleKey(space))
        #expect(sut.model.playerSearch == "apple ")
    }

    @Test("what was typed in the players' search goes as they close; a closing field handing its text back changes nothing")
    func playerSearchCleared() {
        let sut = menuWithManyPlayers()
        defer { sut.remove() }
        sut.perform(.searchPlayers("vl"))
        sut.handle(.left) // closed: what was typed goes with it
        #expect(sut.model.playerSearch.isEmpty)
        sut.perform(.searchPlayers("a")) // a closing field handing its text back changes nothing
        #expect(sut.model.playerSearch.isEmpty)
    }

    @Test("fewer than eight players have no search")
    func noPlayerSearch() {
        let sut = menuWithManyPlayers(7)
        defer { sut.remove() }
        #expect(playerRows(sut).first == "[Supported]") // seven: no search
    }
}
