import AppKit
import Foundation
import OSLog
import AutoHushKit

// MARK: - Spotify playback observer
//
// Spotify posts `com.spotify.client.PlaybackStateChanged` as a distributed
// notification on every play/pause/stop/track change, with the new state in
// userInfo["Player State"] ("Playing", "Paused" or "Stopped"). Observing it
// replaces polling Spotify with Apple events. Spotify posts nothing when it
// quits, so app termination is observed through NSWorkspace instead.

@MainActor
package final class SpotifyPlaybackObserver: NSObject, PlayerStateObserving {
    package static let playbackStateChanged = Notification.Name("com.spotify.client.PlaybackStateChanged")

    private let onChange: @MainActor (PlayerState) -> Void
    private let distributedCenter: DistributedNotificationCenter
    private let workspaceCenter: NotificationCenter
    private var terminationObserver: (any NSObjectProtocol)?
    private var isObserving = false
    private let logger = Logger(category: "SpotifyPlaybackObserver")

    package init(
        distributedCenter: DistributedNotificationCenter = .default(),
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        onChange: @escaping @MainActor (PlayerState) -> Void
    ) {
        self.distributedCenter = distributedCenter
        self.workspaceCenter = workspaceCenter
        self.onChange = onChange
    }

    package func start() {
        guard !isObserving else { return }
        isObserving = true

        // Accessory apps are almost never "active"; without .deliverImmediately
        // distributed notifications would be held back until activation.
        distributedCenter.addObserver(
            self,
            selector: #selector(playbackStateDidChange(_:)),
            name: Self.playbackStateChanged,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        terminationObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let bundleID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication)?.bundleIdentifier
            guard bundleID == SpotifyPlayer.appBundleID else { return }
            MainActor.assumeIsolated { self?.deliver(.notRunning) }
        }
    }

    package func stop() {
        guard isObserving else { return }
        isObserving = false
        distributedCenter.removeObserver(self, name: Self.playbackStateChanged, object: nil)
        if let terminationObserver {
            workspaceCenter.removeObserver(terminationObserver)
        }
        terminationObserver = nil
    }

    /// Maps the notification's "Player State" value to a `PlayerState`.
    package nonisolated static func playerState(from userInfo: [AnyHashable: Any]?) -> PlayerState {
        switch (userInfo?["Player State"] as? String)?.lowercased() {
        case "playing": return .playing
        case "paused":  return .paused
        case "stopped": return .stopped
        default:        return .unknown
        }
    }

    @objc private func playbackStateDidChange(_ notification: Notification) {
        deliver(Self.playerState(from: notification.userInfo))
    }

    private func deliver(_ state: PlayerState) {
        guard isObserving else { return }
        logger.debug("Spotify reported \(state.rawValue, privacy: .public)")
        onChange(state)
    }
}
