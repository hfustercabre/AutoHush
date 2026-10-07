import AppKit
import Foundation
import OSLog
import AutoHushKit

/// What AutoHush needs to know about a music app it controls through its
/// playback menu. Each `<App>Support` module describes its app with one.
package struct MenuPlayerProfile: Sendable {
    package let bundleID: String
    /// Shown to the user, e.g. "TIDAL".
    package let name: String
    /// The menu's English name, for error reports, e.g. "Playback".
    package let menuName: String
    /// Reads the app's own words for Play and Pause from a copy of the app.
    package let readWords: @Sendable (URL) -> PlayPauseWords?
    /// Drawn in place of the app's icon while it isn't installed.
    package let iconPlaceholder: PlayerIconPlaceholder?

    package init(
        bundleID: String,
        name: String,
        menuName: String,
        readWords: @escaping @Sendable (URL) -> PlayPauseWords?,
        iconPlaceholder: PlayerIconPlaceholder? = nil
    ) {
        self.bundleID = bundleID
        self.name = name
        self.menuName = menuName
        self.readWords = readWords
        self.iconPlaceholder = iconPlaceholder
    }
}

/// Controls an app that can't be scripted through its playback menu (see
/// `PlaybackMenu`), which needs the Accessibility permission. Its state is
/// the menu item's title, told apart with the app's own words
/// (`PlayPauseWords`).
///
/// It never presses the item blindly: pausing presses it only while the app
/// plays, playing only while it's paused. Its volume can't be read, so it
/// pauses and plays without fading.
package actor MenuPlayer: MusicPlayer {
    package nonisolated let profile: MenuPlayerProfile

    package nonisolated var bundleID: String { profile.bundleID }
    package nonisolated var name: String { profile.name }
    package nonisolated var iconPlaceholder: PlayerIconPlaceholder? { profile.iconPlaceholder }
    /// It's controlled through its menu, which needs Accessibility.
    package nonisolated var controlPermission: Permission { .accessibility(player: name) }
    /// Its volume can't be read or set.
    package nonisolated var canFade: Bool { false }

    private let menu: any PlaybackMenu
    private let processIdentifier: @Sendable () -> pid_t?
    private let words: @Sendable () -> PlayPauseWords?
    /// macOS's request for Accessibility is shown once per launch, not at
    /// every check.
    private var hasAskedForAccess = false
    private let logger = Logger(category: "MenuPlayer")
    /// Accessibility calls block: they run here, one at a time.
    private let queue: DispatchQueue

    package init(
        profile: MenuPlayerProfile,
        menu: any PlaybackMenu = AccessibilityPlaybackMenu(),
        processIdentifier: (@Sendable () -> pid_t?)? = nil,
        words: (@Sendable () -> PlayPauseWords?)? = nil
    ) {
        self.profile = profile
        self.menu = menu
        // Only a running app is ever controlled, so AutoHush never launches it.
        self.processIdentifier = processIdentifier ?? { [bundleID = profile.bundleID] in
            NSRunningApplication.running(bundleID)?.processIdentifier
        }
        self.words = words ?? { [bundleID = profile.bundleID, read = profile.readWords] in
            PlayPauseWords.installed(bundleID: bundleID, read: read)
        }
        queue = DispatchQueue(label: "AutoHush.\(profile.name)", qos: .userInitiated)
    }

    package func verifyControlAccess() async throws {
        guard let pid = processIdentifier() else { throw MusicPlayerError.playerNotRunning }
        let prompt = !hasAskedForAccess
        hasAskedForAccess = true
        let menu = menu
        guard await onQueue({ menu.isTrusted(prompt: prompt) }) else { throw MusicPlayerError.accessibilityPermissionDenied }
        guard await onQueue({ menu.toggle(pid: pid) }) != nil else {
            throw MusicPlayerError.playerCommandFailed("\(name)'s \(profile.menuName) menu wasn't found")
        }
    }

    package func playerState() async -> PlayerState {
        guard let pid = processIdentifier() else { return .notRunning }
        let menu = menu
        guard await onQueue({ menu.isTrusted(prompt: false) }),
              let toggle = await onQueue({ menu.toggle(pid: pid) })
        else { return .unknown }
        guard toggle.isEnabled else { return .stopped } // nothing to play
        guard let words = await onQueue(words) else { return .unknown }
        return Self.state(of: toggle, words: words)
    }

    package func pause() async throws {
        try await press(from: .playing)
    }

    package func play() async throws {
        try await press(from: .paused)
    }

    /// Its volume can't be read or set: no fades.
    package func volume() async -> Int? { nil }
    package func setVolume(_ volume: Int) async throws {}

    @MainActor
    package func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        PolledStateObserver(read: { [self] in await self.playerState() }, onChange: onChange)
    }

    /// What the Play/Pause item says: "Pause" while the app plays, "Play"
    /// while it's paused. A title in both lists, or neither, says nothing.
    package static func state(of toggle: MenuToggle, words: PlayPauseWords) -> PlayerState {
        switch (words.pause.contains(toggle.title), words.play.contains(toggle.title)) {
        case (true, false): .playing
        case (false, true): .paused
        default: .unknown
        }
    }

    /// Presses Play/Pause if the app is in `state`; does nothing if it's
    /// already in the other one.
    private func press(from state: PlayerState) async throws {
        let current = await playerState()
        guard current == state else {
            if current == .notRunning { throw MusicPlayerError.playerNotRunning }
            if current == .unknown || current == .stopped {
                throw MusicPlayerError.playerCommandFailed("\(name)'s state is \(current.rawValue)")
            }
            return
        }
        guard let pid = processIdentifier() else { throw MusicPlayerError.playerNotRunning }
        let menu = menu
        guard await onQueue({ menu.pressToggle(pid: pid) }) else {
            logger.error("Pressing \(self.name, privacy: .public)'s Play/Pause failed")
            throw MusicPlayerError.playerCommandFailed("\(name)'s Play/Pause couldn't be pressed")
        }
    }

    private func onQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }
}
