import AppKit
import Foundation
import AutoHushKit

/// Reports TIDAL's state changes. TIDAL announces nothing, so its Play/Pause
/// item is read about once a second while observing; quitting is observed
/// through NSWorkspace.
@MainActor
package final class TidalStateObserver: PlayerStateObserving {
    /// How often the menu is read.
    package static let interval: Duration = .seconds(1)

    private let player: TidalPlayer
    private let onChange: @MainActor (PlayerState) -> Void
    private let workspaceCenter: NotificationCenter
    private let interval: Duration
    private var polling: Task<Void, Never>?
    private var terminationObserver: (any NSObjectProtocol)?
    private var lastState: PlayerState?

    package init(
        player: TidalPlayer,
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        interval: Duration = TidalStateObserver.interval,
        onChange: @escaping @MainActor (PlayerState) -> Void
    ) {
        self.player = player
        self.workspaceCenter = workspaceCenter
        self.interval = interval
        self.onChange = onChange
    }

    package func start() {
        guard polling == nil else { return }
        let player = player
        let interval = interval
        polling = Task { [weak self] in
            while !Task.isCancelled {
                let state = await player.playerState()
                // Gone without stop(): nothing more to read for.
                guard !Task.isCancelled, self != nil else { return }
                self?.deliver(state)
                try? await Task.sleep(for: interval)
            }
        }
        terminationObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let terminated = (notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication)?.bundleIdentifier
            guard terminated == TidalPlayer.appBundleID else { return }
            MainActor.assumeIsolated { self?.deliver(.notRunning) }
        }
    }

    package func stop() {
        polling?.cancel()
        polling = nil
        if let terminationObserver { workspaceCenter.removeObserver(terminationObserver) }
        terminationObserver = nil
        lastState = nil
    }

    /// Only changes are reported, and only states that say something.
    private func deliver(_ state: PlayerState) {
        guard polling != nil, state != .unknown, state != lastState else { return }
        lastState = state
        onChange(state)
    }
}
