import AppKit
import Foundation
import OSLog
import AutoHushKit

/// Talks to Spotify with raw Apple events instead of NSAppleScript.
///
/// NSAppleScript is main-thread only: run on a background queue it pumps an
/// event loop while waiting for the reply, which can trap inside BoardServices.
/// `NSAppleEventDescriptor.sendEvent(options:timeout:)` is built on
/// `AESendMessage`, which blocks without running an event loop and is safe on
/// any thread.
package actor SpotifyPlayer: MusicPlayer {
    package static let appBundleID = "com.spotify.client"

    package nonisolated var bundleID: String { Self.appBundleID }
    package nonisolated var name: String { "Spotify" }
    /// Measured on Spotify 1.3.3 for macOS (`swift run measure-volume-curve`):
    /// within 2 dB of a cube law from 15 to 90 (50 → −18 dB, 20 → −40 dB);
    /// 11 is about −54 dB and 10 or less is silent.
    package nonisolated var volumeCurve: VolumeCurve { .cubic }

    private let logger = Logger(category: "SpotifyPlayer")

    /// Serial queue for the blocking sends, so they neither occupy the
    /// cooperative thread pool nor overtake one another.
    private let eventQueue = DispatchQueue(label: "AutoHush.SpotifyPlayer", qos: .userInitiated)

    package init() {}

    /// How long to wait for Spotify to answer an event.
    package static let replyTimeout: TimeInterval = 5

    package func verifyControlAccess() async throws {
        let pid = try runningProcessIdentifier()
        // Ask for consent up front: the send below times out after a few
        // seconds, which is too short for a user reading the TCC prompt.
        let status = try await onEventQueue {
            let target = NSAppleEventDescriptor(processIdentifier: pid)
            return AEDeterminePermissionToAutomateTarget(
                target.aeDesc, Code.coreSuite, Code.getData, true
            )
        }
        if status != noErr {
            throw Self.mapError(number: Int(status), message: nil)
        }
        _ = try await send(Self.makeGetPlayerStateEvent(processIdentifier:), to: pid)
    }

    package func playerState() async -> PlayerState {
        guard let pid = spotifyProcessIdentifier() else { return .notRunning }
        do {
            let reply = try await send(Self.makeGetPlayerStateEvent(processIdentifier:), to: pid)
            return Self.playerState(fromReply: reply)
        } catch {
            logger.error("playerState failed: \(error.localizedDescription, privacy: .public)")
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
        guard let pid = spotifyProcessIdentifier(),
              let reply = try? await send(Self.makeGetVolumeEvent(processIdentifier:), to: pid)
        else { return nil }
        return Self.volume(fromReply: reply)
    }

    package func setVolume(_ volume: Int) async throws {
        let volume = min(max(volume, 0), 100)
        let pid = try runningProcessIdentifier()
        _ = try await send({ Self.makeSetVolumeEvent(volume, processIdentifier: $0) }, to: pid)
    }

    @MainActor
    package func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        SpotifyPlaybackObserver(onChange: onChange)
    }

    // MARK: - Private helpers

    /// Targeting the running process (rather than the bundle ID) guarantees
    /// that an event can never launch Spotify.
    private func spotifyProcessIdentifier() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.appBundleID)
            .first { !$0.isTerminated }?
            .processIdentifier
    }

    /// The running Spotify's pid, for commands that can't do without it.
    private func runningProcessIdentifier() throws -> pid_t {
        guard let pid = spotifyProcessIdentifier() else { throw MusicPlayerError.playerNotRunning }
        return pid
    }

    /// Sends a parameterless Spotify command such as `pause` or `play`.
    private func sendCommand(_ eventID: AEEventID) async throws {
        let pid = try runningProcessIdentifier()
        _ = try await send({ Self.makeCommandEvent(eventID, processIdentifier: $0) }, to: pid)
    }

    /// Builds the event on `eventQueue` (descriptors are not Sendable), sends
    /// it and returns the direct object of the reply as a Sendable value.
    private func send(
        _ makeEvent: @escaping @Sendable (pid_t) -> NSAppleEventDescriptor,
        to pid: pid_t
    ) async throws -> SpotifyReply {
        try await onEventQueue {
            let event = makeEvent(pid)
            let reply: NSAppleEventDescriptor
            do {
                reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: Self.replyTimeout)
            } catch {
                throw Self.mapError(error)
            }
            if let error = Self.replyError(reply) { throw error }
            return SpotifyReply(reply)
        }
    }

    private func onEventQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            eventQueue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }
}
