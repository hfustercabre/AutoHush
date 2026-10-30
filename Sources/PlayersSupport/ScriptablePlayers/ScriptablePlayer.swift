import AppKit
import Foundation
import AutoHushKit

/// Controls a music app with Apple events (see `AppleEventChannel`): its
/// state, pause, play and volume, as described by its profile.
package actor ScriptablePlayer: MusicPlayer {
    nonisolated let profile: ScriptablePlayerProfile

    package nonisolated var bundleID: String { profile.bundleID }
    package nonisolated var name: String { profile.name }
    package nonisolated var volumeCurve: VolumeCurve { profile.volumeCurve }
    package nonisolated var iconPlaceholder: PlayerIconPlaceholder? { profile.iconPlaceholder }

    private let logger = AutoHushLogger(category: "ScriptablePlayer")
    private let channel: any AppleEventSending

    /// `channel`: its Apple events; tests stand in for them.
    package init(profile: ScriptablePlayerProfile, channel: any AppleEventSending? = nil) {
        self.profile = profile
        self.channel = channel ?? AppleEventChannel(bundleID: profile.bundleID, label: profile.name)
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
            logger.error("\(self.profile.name, privacy: .public) playerState failed: \(error)")
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

    /// Its notification announces each change at once.
    package nonisolated var stateReportDelay: TimeInterval { 0 }

    /// Sends a parameterless command of the app's suite, such as pause or play.
    private func sendCommand(_ eventID: AEEventID) async throws {
        let pid = try channel.runningProcessIdentifier()
        let suite = profile.suite
        _ = try await channel.send({ Self.makeCommandEvent(suite: suite, eventID, processIdentifier: $0) }, to: pid)
    }
}
