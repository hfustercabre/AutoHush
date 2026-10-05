import AppKit
import Foundation
import OSLog
import AutoHushKit

/// Reports a music app's state changes without asking the app.
///
/// The scriptable players post a distributed notification on every play,
/// pause, stop and track change (Spotify `com.spotify.client.PlaybackStateChanged`,
/// Music `com.apple.Music.playerInfo`), with the new state in
/// userInfo["Player State"] ("Playing", "Paused" or "Stopped"). Observing it
/// replaces polling the app with Apple events. Nothing is posted when the
/// app quits, so that is observed through NSWorkspace instead.
@MainActor
package final class PlayerStateObserver: NSObject, PlayerStateObserving {
    private let notification: Notification.Name
    private let bundleID: String
    private let onChange: @MainActor (PlayerState) -> Void
    private let distributedCenter: DistributedNotificationCenter
    private let workspaceCenter: NotificationCenter
    private var terminationObserver: (any NSObjectProtocol)?
    private var isObserving = false
    private let logger = Logger(category: "PlayerStateObserver")

    package init(
        notification: Notification.Name,
        bundleID: String,
        distributedCenter: DistributedNotificationCenter = .default(),
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        onChange: @escaping @MainActor (PlayerState) -> Void
    ) {
        self.notification = notification
        self.bundleID = bundleID
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
            name: notification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        let bundleID = bundleID
        terminationObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let terminated = (notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication)?.bundleIdentifier
            guard terminated == bundleID else { return }
            MainActor.assumeIsolated { self?.deliver(.notRunning) }
        }
    }

    package func stop() {
        guard isObserving else { return }
        isObserving = false
        distributedCenter.removeObserver(self, name: notification, object: nil)
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
        logger.debug("\(self.bundleID, privacy: .public) reported \(state.rawValue, privacy: .public)")
        onChange(state)
    }
}
