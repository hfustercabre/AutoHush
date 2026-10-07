import AppKit
import Foundation
import os
import AutoHushKit

/// Controls a Safari web app (YouTube Music, Amazon Music, Spotify's web
/// player, or any other site added to the Dock) by pressing the site's own
/// Play/Pause button through Accessibility, so the site stays in step. Web
/// apps can't be scripted and have no playback menu.
///
/// Sites differ, and their words are in the site's language, so the button
/// is learned by watching the user play and pause the web app once (see
/// `WebAppControl`). Its windows are reached on every Space, minimized ones
/// too. It never presses the button blindly: pausing presses it only while
/// the button says the music plays, playing only while it says it's paused.
/// Its volume can't be read, so it pauses and plays without fading. A pause
/// the site refuses, or an ad that plays while its button says "Play", mutes
/// the web app instead.
package actor SafariWebAppPlayer: LearningMusicPlayer, MutingMusicPlayer {
    package nonisolated let app: SafariWebApp
    /// Its site isn't one AutoHush has been tested with.
    package nonisolated let isUntested: Bool

    package nonisolated var bundleID: String { app.bundleID }
    package nonisolated var name: String { app.name }
    package nonisolated var kind: MusicPlayerKind { .safariWebApp }
    package nonisolated var installedURL: URL? { app.url }
    /// Its page is read and pressed through Accessibility.
    package nonisolated var controlPermission: Permission { .accessibility(player: name) }
    /// Its volume can't be read or set.
    package nonisolated var canFade: Bool { false }

    private let page: any WebPage
    private let processIdentifier: @Sendable () -> pid_t?
    private let status = LearningStatusBroadcast()
    private let tapsAllowed = OSAllocatedUnfairLock(initialState: true)
    /// Used only on `queue`.
    private nonisolated let control: WebAppControl
    /// macOS's request for Accessibility is shown once per launch, not at
    /// every check.
    private var hasAskedForAccess = false
    /// Accessibility calls block: they run here, one at a time.
    private let queue: DispatchQueue

    package init(
        app: SafariWebApp,
        isUntested: Bool = false,
        page: any WebPage = AccessibilityWebPage(),
        store: any PlayPauseRecipeStore = DefaultsRecipeStore(),
        muter: any AudioMuting = ProcessTapMuter(),
        levelProbe: any AudioLevelProbing = ProcessTapLevelProbe(),
        processIdentifier: (@Sendable () -> pid_t?)? = nil,
        clock: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) {
        self.app = app
        self.isUntested = isUntested
        self.page = page
        // Only a running app is ever controlled, so AutoHush never opens it.
        self.processIdentifier = processIdentifier ?? { [bundleID = app.bundleID] in
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first { !$0.isTerminated }?
                .processIdentifier
        }
        control = WebAppControl(name: app.name, bundleID: app.bundleID, page: page, store: store, status: status,
                                muter: muter, levelProbe: levelProbe, mayMute: { [tapsAllowed] in tapsAllowed.withLock { $0 } },
                                clock: clock, sleep: sleep)
        queue = DispatchQueue(label: "AutoHush.WebApp.\(app.bundleID)", qos: .userInitiated)
    }

    package nonisolated var learningStatus: LearningStatus { status.current }

    package nonisolated func learningUpdates() -> AsyncStream<LearningStatus> { status.updates() }

    package nonisolated func allowTaps(_ allowed: Bool) {
        tapsAllowed.withLock { $0 = allowed }
    }

    /// Needs the app running and Accessibility, not the button learned: it's
    /// learned while the state is read.
    package func verifyControlAccess() async throws {
        guard processIdentifier() != nil else { throw MusicPlayerError.playerNotRunning }
        let prompt = !hasAskedForAccess
        hasAskedForAccess = true
        let page = page
        guard await onQueue({ page.isTrusted(prompt: prompt) }) else { throw MusicPlayerError.accessibilityPermissionDenied }
    }

    package func playerState() async -> PlayerState {
        guard let pid = processIdentifier() else { return .notRunning }
        let page = page
        guard await onQueue({ page.isTrusted(prompt: false) }) else { return .unknown }
        let control = control
        return await onQueue { control.state(pid: pid) }
    }

    package func pause() async throws {
        try await press(from: .playing)
    }

    package func muteIfPlayingAnyway() async -> Bool {
        guard let pid = processIdentifier() else { return false }
        let control = control
        return await onQueue { control.muteIfPlayingAnyway(pid: pid) }
    }

    package func forgetPause() async {
        let control = control
        await onQueue { control.forgetPause() }
    }

    package func play() async throws {
        try await press(from: .paused)
    }

    /// Its volume can't be read or set: no fades.
    package func volume() async -> Int? { nil }
    package func setVolume(_ volume: Int) async throws {}

    /// Read about once a second; when it stops (monitoring stops), a mute
    /// in place of a pause is lifted, so the web app is never left silent.
    @MainActor
    package func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        WebAppStateObserver(
            polled: PolledStateObserver(read: { [self] in await self.playerState() }, onChange: onChange),
            onStop: { [self] in Task { await self.releaseMute() } }
        )
    }

    /// Lifts a mute in place of a pause, without playing anything.
    package func releaseMute() async {
        let control = control
        await onQueue { control.releaseMute() }
    }

    private func press(from state: PlayerState) async throws {
        guard let pid = processIdentifier() else { throw MusicPlayerError.playerNotRunning }
        let control = control
        let result: Result<Void, any Error> = await onQueue {
            Result { try control.press(from: state, pid: pid) }
        }
        try result.get()
    }

    private func onQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }
}

/// A web app's state observer: the polled one, and lifting a mute when it stops.
@MainActor
final class WebAppStateObserver: PlayerStateObserving {
    private let polled: PolledStateObserver
    private let onStop: @MainActor () -> Void

    init(polled: PolledStateObserver, onStop: @escaping @MainActor () -> Void) {
        self.polled = polled
        self.onStop = onStop
    }

    func start() { polled.start() }

    func stop() {
        polled.stop()
        onStop()
    }
}

/// The Safari web apps on this Mac as players, each kept as long as it's
/// installed: a player remembers its button and how learning goes.
package final class SafariWebAppPlayers: Sendable {
    private let finder: SafariWebAppFinder
    private let tested: [TestedWebApp]
    private let makePlayer: @Sendable (SafariWebApp, _ isUntested: Bool) -> SafariWebAppPlayer
    private let players = OSAllocatedUnfairLock<[String: SafariWebAppPlayer]>(initialState: [:])

    /// `tested`: the sites AutoHush has been tested with; any other web app
    /// is untested.
    package init(
        finder: SafariWebAppFinder = SafariWebAppFinder(),
        tested: [TestedWebApp] = [],
        makePlayer: @escaping @Sendable (SafariWebApp, _ isUntested: Bool) -> SafariWebAppPlayer = {
            SafariWebAppPlayer(app: $0, isUntested: $1)
        }
    ) {
        self.finder = finder
        self.tested = tested
        self.makePlayer = makePlayer
    }

    /// One player for each web app installed now, by name; a tested site's
    /// is named as the site ("YouTube Music", whatever Safari called it). A
    /// web app that was renamed or moved gets a new one.
    package func current() -> [SafariWebAppPlayer] {
        let apps = finder.webApps().map(named).sorted { $0.name.localizedLowercase < $1.name.localizedLowercase }
        return players.withLock { players in
            let kept = players
            players = [:]
            return apps.map { app in
                let player = kept[app.bundleID].flatMap { $0.app == app ? $0 : nil }
                    ?? makePlayer(app, !tested.contains { $0.isAdded(as: app) })
                players[app.bundleID] = player
                return player
            }
        }
    }

    /// `app`, named as its tested site when it's one's.
    private func named(_ app: SafariWebApp) -> SafariWebApp {
        guard let site = tested.first(where: { $0.isAdded(as: app) }), site.name != app.name else { return app }
        return SafariWebApp(bundleID: app.bundleID, name: site.name, url: app.url, startURL: app.startURL)
    }

    /// The tested sites that no web app installed now opens, to suggest.
    package func suggestions() -> [WebAppSuggestion] {
        TestedWebApp.notAdded(tested, among: finder.webApps())
    }
}
