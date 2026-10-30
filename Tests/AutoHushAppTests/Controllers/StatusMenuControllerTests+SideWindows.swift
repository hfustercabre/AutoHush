import AppKit
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

extension StatusMenuControllerTests {
    @Test("Ignored Apps names one or two apps, then the first two and how many more", arguments: [
        ([String](), ""), (["VLC"], "VLC"), (["VLC", "Messages"], ListFormatter.localizedString(byJoining: ["VLC", "Messages"])),
        (["VLC", "Messages", "Chrome"], "VLC, Messages and 1 more"), (["VLC", "Messages", "Chrome", "Mail"], "VLC, Messages and 2 more"),
    ])
    func ignoredAppsNames(names: [String], expected: String) {
        #expect(MenuIgnoredAppsView.names(of: names) == expected)
    }

    @Test("Ignored Apps says what ignoring does in the singular for one app, in the plural for more, and what it would do for none")
    func ignoredAppsSubtitle() {
        #expect(MenuIgnoredAppsView.subtitle(count: 0) == "Apps you ignore don’t pause your player.")
        #expect(MenuIgnoredAppsView.subtitle(count: 1) == "It doesn’t pause your player.")
        #expect(MenuIgnoredAppsView.subtitle(count: 2) == "They don’t pause your player.")
        #expect(MenuIgnoredAppsView.subtitle(count: 5) == "They don’t pause your player.")
    }

    /// The menu open, Ignored Apps listing VLC.
    func menuIgnoringVLC() -> StatusMenuController {
        let sut = makeController()
        var status = readyStatus()
        status.ignoredApps = [vlc]
        sut.status = status
        reopen(sut)
        return sut
    }

    @Test("the pointer passing over a row doesn't open its side window")
    func sideWindowsOnHover() async {
        let sut = menuIgnoringVLC()
        defer { sut.remove() }
        sut.perform(.hoverSideRow(.players, true))
        sut.perform(.hoverSideRow(.players, false)) // only passing over it
        await sut.sideOpenTask?.value
        #expect(sut.model.openSide == nil)
    }

    @Test("the pointer resting on a row opens its side window")
    func sideWindowOpensOnRest() async {
        let sut = menuIgnoringVLC()
        defer { sut.remove() }
        sut.perform(.hoverSideRow(.players, true))
        await sut.sideOpenTask?.value
        #expect(sut.model.openSide == .players)
    }

    @Test("a side window stays open with the pointer on its own part, or back on it within a moment")
    func sideWindowStaysOnItsPart() async {
        let sut = menuIgnoringVLC()
        defer { sut.remove() }
        sut.perform(.hoverSideRow(.players, true))
        await sut.sideOpenTask?.value
        sut.perform(.pointerEntered(.card)) // the card, told while on its Change Player row: stays
        sut.perform(.pointerEntered(.snooze))
        sut.perform(.pointerEntered(.playerRow)) // back before the moment is over
        await sut.sideCloseTask?.value
        #expect(sut.model.openSide == .players)
    }

    @Test("the pointer resting on the rest of the card closes the players' side window, as on another part")
    func playersCloseOnTheCard() async {
        let sut = menuIgnoringVLC()
        defer { sut.remove() }
        sut.perform(.hoverSideRow(.players, true))
        await sut.sideOpenTask?.value
        #expect(sut.model.openSide == .players)
        sut.perform(.hoverSideRow(.players, false)) // off Change Player, onto the card
        sut.perform(.pointerEntered(.card))
        await sut.sideCloseTask?.value
        #expect(sut.model.openSide == nil)
    }

    @Test("the pointer on another part closes the side window after a moment")
    func sideWindowClosesOnAnotherPart() async {
        let sut = menuIgnoringVLC()
        defer { sut.remove() }
        sut.perform(.hoverSideRow(.players, true))
        await sut.sideOpenTask?.value
        #expect(sut.model.openSide == .players) // it opened, first
        sut.perform(.pointerEntered(.ignoredApps))
        await sut.sideCloseTask?.value
        #expect(sut.model.openSide == nil)
    }

    @Test("a click on a row opens its side window, and never closes it")
    func sideWindowOpensOnClick() {
        let sut = menuIgnoringVLC()
        defer { sut.remove() }
        sut.perform(.openSide(.ignoredApps))
        sut.perform(.openSide(.ignoredApps)) // a click on its row again: still open
        #expect(sut.model.openSide == .ignoredApps && sut.model.listedIgnoredApps == [vlc])
    }

    @Test("the pointer resting on another row opens that row's side window instead")
    func sideWindowSwitchesRows() async {
        let sut = menuIgnoringVLC()
        defer { sut.remove() }
        sut.perform(.openSide(.ignoredApps))
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

    // MARK: - Rows

    @Test("Ignored Apps shows with no app ignored too")
    func ignoredApps() {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        status.setActiveSources([vlc, chrome])
        sut.status = status
        reopen(sut)
        #expect(parts(sut).contains("ignoredApps")) // none yet: the first is added from it
    }

    /// The menu open with VLC and Chrome playing, VLC ignored.
    private func menuWithVLCIgnored() -> (sut: StatusMenuController, status: AppStatus) {
        let sut = makeController()
        var status = readyStatus()
        status.setActiveSources([vlc, chrome])
        status.ignoredApps = [vlc]
        sut.status = status
        reopen(sut)
        return (sut, status)
    }

    @Test("Ignored Apps' row opens its side window, listing the apps ignored")
    func ignoredAppsSideWindow() {
        let (sut, _) = menuWithVLCIgnored()
        defer { sut.remove() }
        #expect(parts(sut) == ["card", "snooze", "playingNow", "ignoredApps", "toolbar"])
        #expect(sut.model.openSide == nil)
        sut.perform(.openSide(.ignoredApps))
        #expect(sut.model.openSide == .ignoredApps && sut.model.listedIgnoredApps == [vlc])
    }

    @Test("an app's switch in Ignored Apps stops ignoring it, the menu staying open")
    func ignoredAppSwitchedOn() {
        let (sut, _) = menuWithVLCIgnored()
        defer { sut.remove() }
        sut.perform(.openSide(.ignoredApps))
        settings.setIgnored(vlc, true)
        sut.perform(.setIgnored(vlc, false)) // as its switch sends it
        #expect(settings.state.ignoredApps.isEmpty && sut.isMenuOpen)
    }

    @Test("an app no longer ignored keeps its row in Ignored Apps' side window while it's open, and Ignored Apps stays")
    func ignoredAppKeepsItsRow() {
        let (sut, ignoring) = menuWithVLCIgnored()
        defer { sut.remove() }
        sut.perform(.openSide(.ignoredApps))
        var status = ignoring
        status.ignoredApps = []
        sut.status = status
        #expect(sut.model.listedIgnoredApps == [vlc]) // its side window keeps its row
        #expect(parts(sut).contains("ignoredApps"))
    }

    @Test("one side window at a time: the players' opens instead of Ignored Apps'")
    func oneSideWindowAtATime() {
        let (sut, _) = menuWithVLCIgnored()
        defer { sut.remove() }
        sut.perform(.openSide(.ignoredApps))
        sut.perform(.openSide(.players)) // the players' instead
        #expect(sut.model.openSide == .players)
    }

    @Test("a side window is closed each time the menu opens")
    func sideWindowClosedAsTheMenuOpens() {
        let (sut, _) = menuWithVLCIgnored()
        defer { sut.remove() }
        sut.perform(.openSide(.players))
        reopen(sut)
        #expect(sut.model.openSide == nil) // closed each time the menu opens
    }

    @Test("once the user went to allow audio recording, its row reopens AutoHush, and AntiDot mode is offered instead")
    func reopenRow() async {
        let sut = makeController(settingsModel: SettingsModel.forTests(actions: actions, updates: updates, settings: settings))
        defer { sut.remove() }
        var status = readyStatus()
        status.detection = .unavailable
        status.awaitsReopenForAudioRecording = true
        sut.status = status
        reopen(sut)

        #expect(parts(sut).prefix(4) == ["card", "Reopen AutoHush", "Use AntiDot Mode Instead", "snooze"])
        sut.perform(.reopenAutoHush)
        sut.perform(.useAntiDotMode)
        await TestWait.until { settings.state.detection == .playbackSignals }
        #expect(log.calls == ["menuWillOpen", "reopen"])
    }

    @Test("the menu's Use AntiDot Mode Instead goes through Settings' guard: never for a player only its sound tells about")
    func useAntiDotGuarded() async {
        let settingsModel = SettingsModel.forTests(actions: actions, updates: updates, settings: settings)
        var muted = PlayerOption(bundleID: "com.example.muted", name: "Muted", appURL: URL(fileURLWithPath: "/Applications/Muted.app"),
                                 kind: .checkedApp)
        muted.pausesByMuting = true
        muted.needsAudioLevels = true
        settingsModel.state.status.playerOptions = [muted]
        settingsModel.state.status.chosenPlayerID = muted.bundleID
        let sut = makeController(settingsModel: settingsModel)
        defer { sut.remove() }
        sut.status = readyStatus()
        reopen(sut)

        sut.perform(.useAntiDotMode)
        sut.perform(.reopenAutoHush) // acts after it, once the menu has closed
        await wait(for: 2, in: log)
        #expect(log.calls == ["menuWillOpen", "reopen"])
        #expect(settings.state.detection == .audioLevels)
    }

    @Test("what opens a window or an alert closes the menu first; switches and the side windows act at once")
    func closesMenuFirst() {
        for command: StatusMenuCommand in [.addApp, .addWebApp, .ignoreAnotherApp, .useAntiDotMode, .openSettings, .updates, .quit] {
            #expect(command.closesMenuFirst, "\(command)")
        }
        for command: StatusMenuCommand in [.toggleAutoPause, .choosePlayer("x"), .openSide(.players), .retry] {
            #expect(!command.closesMenuFirst, "\(command)")
        }
    }

    /// The menu open, the player needing Automation access.
    private func menuNeedingAutomation() -> StatusMenuController {
        let sut = makeController()
        var status = AppStatus()
        status.choosePlayer(named: "Jukebox")
        status.setHealth(.needsPermission(.automation(player: "Jukebox")))
        sut.status = status
        reopen(sut)
        return sut
    }

    @Test("the player's missing permission is said once, on the card")
    func warningRow() {
        let sut = menuNeedingAutomation()
        defer { sut.remove() }
        #expect(sut.status.statusLine == "Needs Automation access" && sut.status.missingPermission == .automation(player: "Jukebox"))
        #expect(parts(sut).prefix(2) == ["card", "snooze"]) // no row asking again
    }

    @Test("the card's Allow… asks for the player's missing permission")
    func cardAllowAsks() async {
        let sut = menuNeedingAutomation()
        defer { sut.remove() }
        sut.perform(.resolveWarning(.automation(player: "Jukebox"))) // the card's Allow…
        await wait(for: 2, in: log)
        #expect(log.calls == ["menuWillOpen", "warning Allow Jukebox Automation Access…"])
    }

    @Test("Audio Recording missing while monitoring runs is a row under Media Player")
    func audioRecordingRow() {
        let sut = makeController()
        defer { sut.remove() }
        var running = readyStatus()
        running.detection = .unavailable
        sut.status = running
        reopen(sut)
        #expect(parts(sut).prefix(2) == ["card", "Allow Audio Recording Access…"])
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
