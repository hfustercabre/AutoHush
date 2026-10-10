import AppKit
import Foundation
import OSLog
import AutoHushKit
import ScriptablePlayers

/// Controls VLC with Apple events. Its scripting differs from the other
/// scriptable players' (codes from `VLC.app/Contents/Resources/vlc.sdef`):
/// - `play` toggles between playing and paused, so it's only sent from the
///   opposite state;
/// - `playing` only says whether it plays: with `current time` at -1 there's
///   no item, so it's stopped, otherwise paused;
/// - `audio volume` goes from 0 to 512 (256 is 100%);
/// - it announces nothing, so its state is read about once a second.
package actor VLCPlayer: MusicPlayer {
    package static let appBundleID = "org.videolan.vlc"

    package enum Code {
        package static let suite = fourCharCode("VLC#")
        /// Plays, or pauses while playing.
        package static let playPause = fourCharCode("VLC1")
        package static let playingProperty = fourCharCode("AAPL")
        package static let currentTimeProperty = fourCharCode("AACT")
        package static let audioVolumeProperty = fourCharCode("AAAV")
    }

    /// VLC's highest `audio volume`, matched to AutoHush's 100.
    package static let maximumVolume = 512

    package nonisolated var bundleID: String { Self.appBundleID }
    package nonisolated var name: String { "VLC" }
    package nonisolated var iconPlaceholder: PlayerIconPlaceholder? { .vlc }
    /// VLC sets its output's volume to the cube of its own (`VolumeSet` in
    /// VLC's `modules/audio_output/auhal.c`), so half is about −18 dB.
    package nonisolated var volumeCurve: VolumeCurve { .cubic }

    private let channel: AppleEventChannel
    private let logger = Logger(category: "VLCPlayer")
    /// The last volume read, in VLC's numbers and AutoHush's, so setting it
    /// back restores VLC's exact number rather than a rounded one.
    private var lastVolume: (vlc: Int, volume: Int)?

    package init() {
        channel = AppleEventChannel(bundleID: Self.appBundleID, label: "VLC")
    }

    package func verifyControlAccess() async throws {
        let pid = try channel.runningProcessIdentifier()
        try await channel.requestPermission(pid: pid)
        _ = try await get(Code.playingProperty, from: pid)
    }

    package func playerState() async -> PlayerState {
        guard let pid = channel.processIdentifier() else { return .notRunning }
        do {
            let playing = try await get(Code.playingProperty, from: pid).directObjectBoolean
            guard playing == false else { return playing == true ? .playing : .unknown }
            let time = try await get(Code.currentTimeProperty, from: pid).directObjectInteger
            return Self.state(playing: false, currentTime: time)
        } catch {
            logger.error("VLC playerState failed: \(error.localizedDescription, privacy: .public)")
            return .unknown
        }
    }

    /// VLC's state from its `playing` and `current time` (-1 without an item).
    package static func state(playing: Bool, currentTime: Int?) -> PlayerState {
        if playing { return .playing }
        guard let currentTime else { return .unknown }
        return currentTime < 0 ? .stopped : .paused
    }

    package func pause() async throws {
        try await toggle(from: .playing)
    }

    package func play() async throws {
        try await toggle(from: .paused)
    }

    package func volume() async -> Int? {
        guard let pid = channel.processIdentifier(),
              let vlc = try? await get(Code.audioVolumeProperty, from: pid).directObjectInteger
        else { return nil }
        let volume = Self.volume(fromVLC: vlc)
        lastVolume = (vlc, volume)
        return volume
    }

    package func setVolume(_ volume: Int) async throws {
        let volume = min(max(volume, 0), 100)
        let vlc = lastVolume?.volume == volume ? lastVolume!.vlc : Self.vlcVolume(from: volume)
        let pid = try channel.runningProcessIdentifier()
        _ = try await channel.send({
            ScriptablePlayer.makeSetPropertyEvent(Code.audioVolumeProperty, to: vlc, processIdentifier: $0)
        }, to: pid)
    }

    /// VLC's 0–512 as AutoHush's 0–100.
    package static func volume(fromVLC vlc: Int) -> Int {
        min(max(Int((Double(vlc) * 100 / Double(maximumVolume)).rounded()), 0), 100)
    }

    /// AutoHush's 0–100 as VLC's 0–512.
    package static func vlcVolume(from volume: Int) -> Int {
        Int((Double(volume) * Double(maximumVolume) / 100).rounded())
    }

    @MainActor
    package func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        PolledStateObserver(read: { [self] in await self.playerState() }, onChange: onChange)
    }

    package nonisolated var stateReportDelay: TimeInterval { PolledStateObserver.reportDelay }

    /// Sends Play/Pause if VLC is in `state`; does nothing if it's already in
    /// the other one.
    private func toggle(from state: PlayerState) async throws {
        let current = await playerState()
        guard current == state else {
            if current == .notRunning { throw MusicPlayerError.playerNotRunning }
            if current == .unknown { throw MusicPlayerError.playerCommandFailed(.stateUnknown) }
            return
        }
        let pid = try channel.runningProcessIdentifier()
        _ = try await channel.send({
            ScriptablePlayer.makeCommandEvent(suite: Code.suite, Code.playPause, processIdentifier: $0)
        }, to: pid)
    }

    private func get(_ property: DescType, from pid: pid_t) async throws -> PlayerReply {
        try await channel.send({ ScriptablePlayer.makeGetPropertyEvent(property, processIdentifier: $0) }, to: pid)
    }
}
