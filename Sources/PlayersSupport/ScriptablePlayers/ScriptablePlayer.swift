import AppKit
import Foundation
import OSLog
import AutoHushKit

/// What AutoHush needs to know about a music app it controls with Apple
/// events: its codes (from the scripting dictionary in its bundle), the
/// notification it posts when its state changes, and its quirks. Each
/// `<App>Support` module describes its app with one.
package struct ScriptablePlayerProfile: Sendable {
    package let bundleID: String
    /// Shown to the user, e.g. "Spotify".
    package let name: String
    /// The four-char code of the app's own suite, which holds pause and play.
    package let suite: OSType
    /// Posted as a distributed notification on every play, pause, stop and
    /// track change, with the new state in userInfo["Player State"].
    package let stateNotification: Notification.Name
    /// How the app's volume number maps to loudness; measure it with
    /// `swift run measure-volume-curve <bundle-id>`.
    package let volumeCurve: VolumeCurve
    /// The volume the app was set to, from the one it reports: an app that
    /// reports a different number would otherwise lose a step on every fade
    /// that restores the volume it read.
    package let readVolume: @Sendable (Int) -> Int
    /// Drawn in place of the app's icon while it isn't installed.
    package let iconPlaceholder: PlayerIconPlaceholder?

    package init(
        bundleID: String,
        name: String,
        suite: OSType,
        stateNotification: Notification.Name,
        volumeCurve: VolumeCurve = .linear,
        readVolume: @escaping @Sendable (Int) -> Int = { $0 },
        iconPlaceholder: PlayerIconPlaceholder? = nil
    ) {
        self.bundleID = bundleID
        self.name = name
        self.suite = suite
        self.stateNotification = stateNotification
        self.volumeCurve = volumeCurve
        self.readVolume = readVolume
        self.iconPlaceholder = iconPlaceholder
    }
}

/// Controls a music app with Apple events (see `AppleEventChannel`): its
/// state, pause, play and volume, as described by its profile.
package actor ScriptablePlayer: MusicPlayer {
    package nonisolated let profile: ScriptablePlayerProfile

    package nonisolated var bundleID: String { profile.bundleID }
    package nonisolated var name: String { profile.name }
    package nonisolated var volumeCurve: VolumeCurve { profile.volumeCurve }
    package nonisolated var iconPlaceholder: PlayerIconPlaceholder? { profile.iconPlaceholder }

    private let logger = Logger(category: "ScriptablePlayer")
    private let channel: AppleEventChannel

    package init(profile: ScriptablePlayerProfile) {
        self.profile = profile
        channel = AppleEventChannel(bundleID: profile.bundleID, label: profile.name)
    }

    package func verifyControlAccess() async throws {
        let pid = try channel.runningProcessIdentifier()
        try await channel.requestPermission(pid: pid)
        _ = try await channel.send(Self.makeGetPlayerStateEvent(processIdentifier:), to: pid)
    }

    package func playerState() async -> PlayerState {
        guard let pid = channel.processIdentifier() else { return .notRunning }
        do {
            let reply = try await channel.send(Self.makeGetPlayerStateEvent(processIdentifier:), to: pid)
            return Self.playerState(fromReply: reply)
        } catch {
            logger.error("\(self.profile.name, privacy: .public) playerState failed: \(error.localizedDescription, privacy: .public)")
            return .unknown
        }
    }

    package func pause() async throws {
        try await sendCommand(Code.pause)
    }

    package func play() async throws {
        try await sendCommand(Code.play)
    }

    package func volume() async -> Int? {
        guard let pid = channel.processIdentifier(),
              let reply = try? await channel.send(Self.makeGetVolumeEvent(processIdentifier:), to: pid)
        else { return nil }
        return Self.volume(fromReply: reply, reading: profile.readVolume)
    }

    package func setVolume(_ volume: Int) async throws {
        let volume = min(max(volume, 0), 100)
        let pid = try channel.runningProcessIdentifier()
        _ = try await channel.send({ Self.makeSetVolumeEvent(volume, processIdentifier: $0) }, to: pid)
    }

    @MainActor
    package func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        PlayerStateObserver(notification: profile.stateNotification, bundleID: profile.bundleID, onChange: onChange)
    }

    /// Sends a parameterless command of the app's suite, such as pause or play.
    private func sendCommand(_ eventID: AEEventID) async throws {
        let pid = try channel.runningProcessIdentifier()
        let suite = profile.suite
        _ = try await channel.send({ Self.makeCommandEvent(suite: suite, eventID, processIdentifier: $0) }, to: pid)
    }
}
