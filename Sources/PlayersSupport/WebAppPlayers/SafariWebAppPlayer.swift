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
/// is learned once, from the user saying when the web app plays, and the
/// page once paused, by AutoHush itself or the user (see `WebAppControl`).
/// Its windows are reached on every Space, minimized ones too. It never
/// presses the button blindly: pausing presses it only while the button
/// says the music plays, playing only while it says it's paused.
/// Its volume can't be read, so it pauses and plays without fading. A pause
/// the site refuses, or an ad that plays while its button says "Play", mutes
/// the web app instead.
package actor SafariWebAppPlayer: LearningMusicPlayer, MutingMusicPlayer, FadelessMusicPlayer, PolledMusicPlayer {
    nonisolated let app: SafariWebApp
    /// Its site isn't one AutoHush has been tested with.
    package nonisolated let isUntested: Bool

    package nonisolated var bundleID: String { app.bundleID }
    package nonisolated var name: String { app.name }
    /// A Safari web app, or an app whose page it controls the same way
    /// (`PageAccess`: an Electron, CEF or Flutter app, a Chromium web app).
    package nonisolated let kind: MusicPlayerKind
    /// A press is checked here: one the page refuses mutes it instead (`WebAppControl`).
    package nonisolated var checksItsPresses: Bool { true }
    package nonisolated var installedURL: URL? { app.url }
    /// Its page is read and pressed through Accessibility.
    package nonisolated var controlPermission: Permission { .accessibility(player: name) }

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
    /// Which app is Now Playing (`NowPlayingApp`), and the wait before asking
    /// again: asked off `queue`, since a fresh process answers.
    private let nowPlaying: @Sendable () -> NowPlayingApp.Answer
    private let sleep: @Sendable (TimeInterval) -> Void
    /// Where Now Playing is asked, so the page's polls don't wait for it.
    private static let nowPlayingQueue = DispatchQueue(label: "AutoHush.WebApp.NowPlaying", qos: .userInitiated)

    package init(
        app: SafariWebApp,
        kind: MusicPlayerKind = .safariWebApp,
        isUntested: Bool = false,
        page: any WebPage = AccessibilityWebPage(),
        canMute: Bool = true,
        store: any PlayPauseRecipeStore = DefaultsRecipeStore(),
        muter: any AudioMuting = ProcessTapMuter(),
        levelProbe: any AudioLevelProbing = ProcessTapLevelProbe(),
        processIdentifier: (@Sendable () -> pid_t?)? = nil,
        clock: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        pressKey: @escaping @Sendable () -> Void = { DispatchQueue.main.async { PlayPauseKey.press() } },
        nowPlaying: @escaping @Sendable () -> NowPlayingApp.Answer = { NowPlayingApp.current() },
        audioRecordingAllowed: @escaping @Sendable () -> Bool = { AudioCapturePermission.allowsTaps }
    ) {
        self.app = app
        self.kind = kind
        self.isUntested = isUntested
        self.page = page
        // Only a running app is ever controlled, so AutoHush never opens it.
        self.processIdentifier = processIdentifier ?? { [bundleID = app.bundleID] in
            NSRunningApplication.running(bundleID)?.processIdentifier
        }
        control = WebAppControl(name: app.name, bundleID: app.bundleID, page: page, store: store, status: status,
                                muter: muter, levelProbe: levelProbe,
                                // A Chromium web app plays through its browser: muting it would mute every tab.
                                // Without Audio Recording a tap mutes nothing (the user, 2026-10-20).
                                mayMute: { [tapsAllowed] in canMute && tapsAllowed.withLock { $0 } && audioRecordingAllowed() },
                                pressKey: pressKey, clock: clock, sleep: sleep)
        queue = DispatchQueue(label: "AutoHush.WebApp.\(app.bundleID)", qos: .userInitiated)
        self.nowPlaying = nowPlaying
        self.sleep = sleep
    }

    package nonisolated var learningStatus: LearningStatus { status.current }

    package nonisolated func learningUpdates() -> AsyncStream<LearningStatus> { status.updates() }

    package func learnAgain() async {
        let control = control
        await queue.run { control.learnAgain() }
    }

    package func keepLearned() async {
        let control = control
        await queue.run { control.keepLearned() }
    }

    package func markPlaying() async -> LearningMark {
        let pid = processIdentifier()
        let control = control
        return await queue.run { control.notePlaying(pid: pid) }
    }

    package func pauseByItself() async -> SelfPause {
        let pid = processIdentifier()
        let control = control
        let keyReaches = await Self.nowPlayingQueue.run { [nowPlaying, sleep] in
            WebAppControl.keyReaches(pid: pid, nowPlaying: nowPlaying, sleep: sleep)
        }
        return await queue.run { control.pauseByItself(pid: pid, keyReaches: keyReaches) }
    }

    package func markPaused() async -> LearningMark {
        let pid = processIdentifier()
        let control = control
        return await queue.run { control.notePaused(pid: pid) }
    }

    @discardableResult
    package func restartLearning() async -> Bool {
        let control = control
        return await queue.run { control.restartLearning() }
    }

    package nonisolated func allowTaps(_ allowed: Bool) {
        tapsAllowed.withLock { $0 = allowed }
    }

    /// Turns back off the switch its page needed (another app's page), now
    /// that it's no longer the player; turned on again at the next look.
    package func releasePage() async {
        let page = page
        await queue.run { page.release() }
    }

    /// Needs the app running and Accessibility, not the button learned: it's
    /// learned while the state is read.
    package func verifyControlAccess() async throws {
        guard processIdentifier() != nil else { throw MusicPlayerError.playerNotRunning }
        let prompt = !hasAskedForAccess
        hasAskedForAccess = true
        let page = page
        guard await queue.run({ page.isTrusted(prompt: prompt) }) else { throw MusicPlayerError.accessibilityPermissionDenied }
    }

    package func playerState() async -> PlayerState {
        await readState { $0.state(pid: $1) }
    }

    /// The state for the observer, which reads it about once a second: it
    /// asks the page less while the web app is silent (see `polledState`).
    package func polledPlayerState() async -> PlayerState {
        await readState { $0.polledState(pid: $1) }
    }

    private func readState(_ read: @escaping @Sendable (WebAppControl, pid_t) -> PlayerState) async -> PlayerState {
        guard let pid = processIdentifier() else { return .notRunning }
        let page = page
        guard await queue.run({ page.isTrusted(prompt: false) }) else { return .unknown }
        let control = control
        return await queue.run { read(control, pid) }
    }

    package func pause() async throws {
        try await press(from: .playing)
    }

    package func isMutedForPause() async -> Bool {
        let control = control
        return await queue.run { control.muted != nil }
    }

    package func muteIfPlayingAnyway() async -> Bool {
        guard let pid = processIdentifier() else { return false }
        let control = control
        return await queue.run { control.muteIfPlayingAnyway(pid: pid) }
    }

    package func forgetPause() async {
        let control = control
        await queue.run { control.forgetPause() }
    }

    package func play() async throws {
        try await press(from: .paused)
    }

    /// Read about once a second; when it stops (monitoring stops), a mute
    /// in place of a pause is lifted, so the web app is never left silent.
    @MainActor
    package func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        StoppingObserver(PolledStateObserver(read: { [self] in await self.polledPlayerState() }, onChange: onChange)) { [self] in
            Task { await self.releaseMute() }
        }
    }

    /// Lifts a mute in place of a pause, without playing anything.
    package func releaseMute() async {
        let control = control
        await queue.run { control.releaseMute() }
    }

    private func press(from state: PlayerState) async throws {
        guard let pid = processIdentifier() else { throw MusicPlayerError.playerNotRunning }
        let control = control
        try await queue.runThrowing { try control.press(from: state, pid: pid) }
    }
}
