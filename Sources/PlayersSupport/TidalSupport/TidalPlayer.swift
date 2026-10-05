import AppKit
import Foundation
import OSLog
import AutoHushKit

/// Controls TIDAL through its Playback menu (see `TidalMenu`): TIDAL can't be
/// scripted, so this needs the Accessibility permission. Its state is the
/// menu item's title, told apart with TIDAL's own words (`TidalLabels`).
///
/// It never presses the item blindly: pausing presses it only while TIDAL
/// plays, playing only while it's paused. Its volume can't be read, so it
/// pauses and plays without fading.
package actor TidalPlayer: MusicPlayer {
    package static let appBundleID = "com.tidal.desktop"

    package nonisolated var bundleID: String { Self.appBundleID }
    package nonisolated var name: String { "TIDAL" }
    package nonisolated var iconPlaceholder: PlayerIconPlaceholder? { .tidal }
    /// Its volume can't be read or set.
    package nonisolated var canFade: Bool { false }

    private let menu: any TidalMenu
    private let processIdentifier: @Sendable () -> pid_t?
    private let labels: @Sendable () -> TidalLabels?
    /// macOS's request for Accessibility is shown once per launch, not at
    /// every check.
    private var hasAskedForAccess = false
    private let logger = Logger(category: "TidalPlayer")
    /// Accessibility calls block: they run here, one at a time.
    private let queue = DispatchQueue(label: "AutoHush.TIDAL", qos: .userInitiated)

    package init(
        menu: any TidalMenu = AccessibilityTidalMenu(),
        processIdentifier: @escaping @Sendable () -> pid_t? = TidalPlayer.runningProcessIdentifier,
        labels: @escaping @Sendable () -> TidalLabels? = TidalLabels.installed
    ) {
        self.menu = menu
        self.processIdentifier = processIdentifier
        self.labels = labels
    }

    /// The running TIDAL's pid. Only a running TIDAL is ever controlled, so
    /// AutoHush never launches it.
    package static let runningProcessIdentifier: @Sendable () -> pid_t? = {
        NSRunningApplication.runningApplications(withBundleIdentifier: appBundleID)
            .first { !$0.isTerminated }?
            .processIdentifier
    }

    package func verifyControlAccess() async throws {
        guard let pid = processIdentifier() else { throw MusicPlayerError.playerNotRunning }
        let prompt = !hasAskedForAccess
        hasAskedForAccess = true
        let menu = menu
        guard await onQueue({ menu.isTrusted(prompt: prompt) }) else { throw MusicPlayerError.accessibilityPermissionDenied }
        guard await onQueue({ menu.toggle(pid: pid) }) != nil else {
            throw MusicPlayerError.playerCommandFailed("TIDAL's Playback menu wasn't found")
        }
    }

    package func playerState() async -> PlayerState {
        guard let pid = processIdentifier() else { return .notRunning }
        let menu = menu
        guard await onQueue({ menu.isTrusted(prompt: false) }),
              let toggle = await onQueue({ menu.toggle(pid: pid) })
        else { return .unknown }
        guard toggle.isEnabled else { return .stopped } // nobody logged in
        guard let labels = await onQueue(labels) else { return .unknown }
        return Self.state(of: toggle, labels: labels)
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
        TidalStateObserver(player: self, onChange: onChange)
    }

    /// What the Play/Pause item says: "Pause" while TIDAL plays, "Play"
    /// while it's paused. A title in both lists, or neither, says nothing.
    package static func state(of toggle: TidalToggle, labels: TidalLabels) -> PlayerState {
        switch (labels.pause.contains(toggle.title), labels.play.contains(toggle.title)) {
        case (true, false): .playing
        case (false, true): .paused
        default: .unknown
        }
    }

    /// Presses Play/Pause if TIDAL is in `state`; does nothing if it's
    /// already in the other one.
    private func press(from state: PlayerState) async throws {
        let current = await playerState()
        guard current == state else {
            if current == .notRunning { throw MusicPlayerError.playerNotRunning }
            if current == .unknown || current == .stopped {
                throw MusicPlayerError.playerCommandFailed("TIDAL's state is \(current.rawValue)")
            }
            return
        }
        guard let pid = processIdentifier() else { throw MusicPlayerError.playerNotRunning }
        let menu = menu
        guard await onQueue({ menu.pressToggle(pid: pid) }) else {
            logger.error("Pressing TIDAL's Play/Pause failed")
            throw MusicPlayerError.playerCommandFailed("TIDAL's Play/Pause couldn't be pressed")
        }
    }

    private func onQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }
}
