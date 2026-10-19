import AppKit
import Foundation
import SwiftUI
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

/// The menu and its side windows drawn as their windows draw them, in the
/// states the menu shows most: no test opens them on screen.
@Suite("The menu, drawn", .timeLimit(.minutes(1)))
@MainActor
struct MenuPanelViewTests {
    private let actions = FakeAppActions()
    private let settings = UserSettings.inMemory()
    private let session = PlayerSession.noPlayer()
    private let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC")
    private let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome")
    private let safari = AudioSource(id: "com.apple.Safari", name: "Safari")

    /// Enough players for the side window's search: supported apps (one not
    /// installed), an app added with Add an App, and a web app.
    private var players: [PlayerOption] {
        (1...8).map { PlayerOption(bundleID: "com.example.player\($0)", name: "Player \($0)",
                                   appURL: $0 == 8 ? nil : URL(fileURLWithPath: "/Applications/Player \($0).app")) }
            + [PlayerOption(bundleID: "com.example.added", name: "Added", appURL: URL(fileURLWithPath: "/Applications/Added.app"),
                            kind: .checkedApp),
               PlayerOption(bundleID: "com.apple.Safari.WebApp.TEST", name: "YT Music",
                            appURL: URL(fileURLWithPath: "/Users/test/Applications/YT Music.app"), kind: .safariWebApp)]
    }

    /// What the menu shows.
    enum State: String, CaseIterable, Sendable {
        /// Paused for two apps, one played before, one ignored; an update found.
        case paused
        case playing
        /// Audio Recording missing: its warning, and AntiDot mode offered.
        case needsPermission
        /// No player chosen yet.
        case noPlayer
        /// Detection's and Fades' other settings unfolded.
        case moreSettings
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
            status.setActiveSources([vlc, chrome]) // Safari played before
            status.ignoredApps = [chrome]
            status.playback = .pausedByMonitor
            let release = AppRelease(version: AppVersion("0.3.0")!, pageURL: URL(string: "https://example.com")!)
            status.updateOffer = UpdateOffer(release: release, state: .available)
        case .needsPermission:
            status.setHealth(.needsPermission(.systemAudioRecording))
        case .playing, .moreSettings, .noPlayer:
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
        if state == .moreSettings { sut.model.unfoldedSettings = [.detection, .fades] }
        try body(sut, settingsModel)
    }

    @Test("the menu draws in each state, every part it lists in it", arguments: State.allCases)
    func menu(_ state: State) {
        withMenu(state) { sut, settingsModel in
            #expect(sut.model.sections.contains(.settings))
            if state == .paused {
                #expect(sut.model.sections.contains(.playingNow) && sut.model.sections.contains(.recentlyPlayed))
                #expect(sut.model.sections.contains(.update))
            }
            if state == .needsPermission { #expect(sut.model.sections.contains(.useAntiDot)) }
            let size = drawn(MenuPanelView(model: sut.model, settings: settingsModel, onHeight: { _ in }), width: menuContentWidth)
            #expect(size.height > 0)
        }
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
