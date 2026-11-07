import AppKit
import Foundation
import SwiftUI
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

/// The menu and its side windows drawn as their windows draw them, in the
/// states the menu shows most: no test opens them on screen.
@Suite("The menu, drawn", .application, .waitsTimeLimit)
@MainActor
struct MenuPanelViewTests {
    private let actions = FakeAppActions()
    private let settings = UserSettings.inMemory()
    private let session = PlayerSession.noPlayer()
    private let viewer = AudioSource(id: "org.example.viewer", name: "Viewer")
    private let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome")
    private let safari = AudioSource(id: "com.apple.Safari", name: "Safari")

    /// Enough players for the side window's search: supported apps (one not
    /// installed), an app added with Add an App, and a web app.
    private var players: [PlayerOption] {
        (1...8).map { PlayerOption(bundleID: "com.example.player\($0)", name: "Player \($0)",
                                   appURL: $0 == 8 ? nil : URL(fileURLWithPath: "/Applications/Player \($0).app")) }
            + [PlayerOption(bundleID: "com.example.added", name: "Added", appURL: URL(fileURLWithPath: "/Applications/Added.app"),
                            kind: .checkedApp),
               PlayerOption(bundleID: "com.apple.Safari.WebApp.TEST", name: "Yodel Music",
                            appURL: URL(fileURLWithPath: "/Users/test/Applications/Yodel Music.app"), kind: .safariWebApp)]
    }

    /// What the menu shows.
    enum State: String, CaseIterable, Sendable {
        /// Paused for two apps, one played before, one ignored; an update found.
        case paused
        case playing
        /// Audio Recording missing for the player: the card asks for it (no
        /// warning row: `StatusMenuModel.sections`), and AntiDot mode offered.
        case needsPermission
        /// Audio Recording missing while monitoring runs: its warning row
        /// ("Allow Audio Recording Access…") under the card, and AntiDot mode offered.
        case audioRecordingMissing
        /// Audio Recording allowed, AutoHush yet to reopen for it: Reopen AutoHush in the warning's place.
        case awaitsReopen
        /// Auto-Pause turned off for 15 minutes: "Turned off for", its duration selected and the time left.
        case snoozed
        /// No player chosen yet.
        case noPlayer
        /// The player must be reopened, and is muted for another app: the
        /// card's Reopen and Unmute.
        case fixes
        /// The player says it plays, but nothing of it is heard (a muted trailer).
        case playingSilently
        /// A web app whose controls are learned: the card's Learn Again.
        case learnedControls
        /// A resume given up: the card's Try Again.
        case resumeGivenUp
    }

    private func status(_ state: State) -> AppStatus {
        var status = AppStatus()
        guard state != .noPlayer else {
            status.setHealth(.waitingForPlayer)
            return status
        }
        status.playerOptions = players
        status.chosenPlayerID = players[0].bundleID
        status.setHealth(.ready)
        switch state {
        case .paused:
            status.setActiveSources([safari])
            status.setActiveSources([viewer, chrome]) // Safari played before
            status.ignoredApps = [chrome]
            status.playback = .pausedByMonitor
            let release = AppRelease.github("0.3.0", diskImage: false)
            status.updateOffer = UpdateOffer(release: release, state: .available)
        case .needsPermission:
            status.setHealth(.needsPermission(.systemAudioRecording))
        case .audioRecordingMissing, .awaitsReopen:
            status.detection = .unavailable
            status.awaitsReopenForAudioRecording = state == .awaitsReopen
            status.playback = .musicPlaying
        case .snoozed:
            status.autoPause = .snoozed("until 15:42")
            status.snooze = RunningSnooze(end: Date().addingTimeInterval(15 * 60), duration: .fifteenMinutes)
            status.playback = .musicPlaying
        case .fixes:
            status.playerOptions[0].pausesByMuting = true
            status.playerNeedsReopen = true
            status.setActiveSources([viewer])
            status.playback = .pausedByMonitor
        case .playingSilently:
            status.playback = .playingSilently
        case .learnedControls:
            status.chosenPlayerID = players.last?.bundleID // the web app
            status.learning = .learned
            status.playback = .musicPlaying
        case .resumeGivenUp:
            status.playback = .musicIdle
            status.resumeError = ControlError(MusicPlayerError.playerNotResponding, player: players[0].name)
        case .playing, .noPlayer:
            status.playback = .musicPlaying
        }
        return status
    }

    /// The menu put together for `state`, as it opens (its window not
    /// shown), with its settings; removed from the menu bar after `body`.
    private func withMenu(_ state: State, _ body: (StatusMenuController, SettingsModel) throws -> Void) rethrows {
        let settingsModel = SettingsModel.forTests(actions: actions, settings: settings)
        let sut = StatusMenuController(settings: settings, session: session, updates: FakeUpdateCommands(), actions: actions,
                                       settingsModel: settingsModel)
        defer { sut.remove() }
        sut.notificationCenter = NotificationCenter()
        sut.workspaceCenter = NotificationCenter()
        sut.status = status(state)
        sut.open(showsPanel: false)
        try body(sut, settingsModel)
    }

    @Test("the menu draws in each state, every part it lists in it", arguments: State.allCases)
    func menu(_ state: State) {
        withMenu(state) { sut, settingsModel in
            // The card (with Change Player) first, the buttons last; the settings are Settings' only.
            #expect(sut.model.sections.first == .card && sut.model.sections.last == .toolbar)
            if state == .paused {
                #expect(sut.model.sections.contains(.playingNow) && sut.model.sections.contains(.recentlyPlayed))
                #expect(sut.model.sections.contains(.update))
            }
            if state == .needsPermission {
                #expect(sut.model.sections.contains(.useAntiDot))
                #expect(!sut.model.sections.contains(.warning(.systemAudioRecording))) // the card's to ask
            }
            if state == .audioRecordingMissing {
                #expect(sut.model.sections.contains(.warning(.systemAudioRecording)) && sut.model.sections.contains(.useAntiDot))
            }
            if state == .awaitsReopen {
                #expect(sut.model.sections.contains(.reopenAutoHush) && !sut.model.sections.contains(.warning(.systemAudioRecording)))
            }
            if state == .snoozed {
                #expect(sut.model.runningSnoozeDuration == .fifteenMinutes && sut.model.snoozeTimeLeft != nil)
            }
            if state == .fixes { #expect(sut.status.playerNeedsReopen && sut.status.isReady && sut.status.offersUnmute) }
            if state == .playingSilently { #expect(sut.status.statusLine == "Playing silently") }
            if state == .learnedControls { #expect(sut.status.canLearnControlsAgain) }
            if state == .resumeGivenUp { #expect(sut.status.showsResumeFailure && !sut.status.canRetry) }
            let size = drawn(MenuPanelView(model: sut.model, settings: settingsModel, onHeight: { _ in }), width: menuContentWidth)
            #expect(size.height > 0)
        }
    }

    @Test("after a given-up resume, the card draws Try Again under its line")
    func tryAgainAfterGivenUpResume() {
        withMenu(.resumeGivenUp) { sut, settingsModel in
            @MainActor func cardHeight() -> CGFloat { drawn(StatusCardView(model: sut.model, settings: settingsModel), width: menuContentWidth).height }
            let givenUp = cardHeight()
            sut.status.resumeError = nil
            let chip = drawn(PlayerFixButtons.tryAgain(inCard: true) {}, width: menuContentWidth).height
            let plain = cardHeight()
            // Taller by the chip at least: its longer line may wrap too.
            #expect(givenUp >= plain + chip, "\(givenUp) given up, \(plain) without, the chip \(chip)")
        }
    }

    @Test("the menu draws its warning while the player's backup controls stand in for its own way, under the card (B-5)")
    func backupsStandIn() async {
        @MainActor func menuHeight(_ model: SettingsModel) -> (height: CGFloat, sections: [MenuSection]) {
            let menu = StatusMenuModel(status: model.state.status)
            menu.settings = model
            return (drawn(MenuPanelView(model: menu, settings: model, onHeight: { _ in }), width: menuContentWidth).height, menu.sections)
        }
        let standingIn = menuHeight(await SettingsModel.withAutomation(OSStatus(errAEEventNotPermitted), actions: actions))
        let allowed = menuHeight(await SettingsModel.withAutomation(noErr, actions: actions))
        #expect(standingIn.sections.contains(.backupsStandIn(.automation(player: "Jukebox"))))
        #expect(!allowed.sections.contains { if case .backupsStandIn = $0 { true } else { false } })
        #expect(standingIn.height > allowed.height) // the row, drawn
    }

    @Test("both side windows draw: the players, with their search, and the ignored apps", arguments: [MenuSidePart.players, .ignoredApps])
    func sideWindow(_ part: MenuSidePart) {
        withMenu(.paused) { sut, _ in
            sut.perform(.openSide(part))
            #expect(sut.model.openSide == part)
            if part == .players { #expect(sut.model.players.showsSearch) }
            let size = drawn(MenuSidePanelView(model: sut.model, onHeight: { _ in }), width: MenuSidePanelView.width)
            #expect(size.height > 0)
        }
    }
}
