import AppKit
import Foundation
import OSLog

/// Talks to Spotify with raw Apple events instead of NSAppleScript.
///
/// NSAppleScript is main-thread only: run on a background queue it pumps an
/// event loop while waiting for the reply, which can trap inside BoardServices.
/// `NSAppleEventDescriptor.sendEvent(options:timeout:)` is built on
/// `AESendMessage`, which blocks without running an event loop and is safe on
/// any thread.
actor SpotifyPlayer: MusicPlayer {
    static let appBundleID = "com.spotify.client"

    nonisolated var bundleID: String { Self.appBundleID }
    nonisolated var name: String { "Spotify" }

    private let logger = Logger(category: "SpotifyPlayer")

    /// Serial queue for the blocking sends, so they neither occupy the
    /// cooperative thread pool nor overtake one another.
    private let eventQueue = DispatchQueue(label: "AutoHush.SpotifyPlayer", qos: .userInitiated)

    /// How long to wait for Spotify to answer an event.
    static let replyTimeout: TimeInterval = 5

    func verifyControlAccess() async throws {
        guard let pid = spotifyProcessIdentifier() else { throw AutoHushError.playerNotRunning }
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

    func playerState() async -> PlayerState {
        guard let pid = spotifyProcessIdentifier() else { return .notRunning }
        do {
            let reply = try await send(Self.makeGetPlayerStateEvent(processIdentifier:), to: pid)
            return Self.playerState(fromReply: reply)
        } catch {
            logger.error("playerState failed: \(error.localizedDescription, privacy: .public)")
            return .unknown
        }
    }

    func pause() async throws {
        guard let pid = spotifyProcessIdentifier() else { throw AutoHushError.playerNotRunning }
        _ = try await send({ Self.makeCommandEvent(Code.pause, processIdentifier: $0) }, to: pid)
    }

    func play() async throws {
        guard let pid = spotifyProcessIdentifier() else { throw AutoHushError.playerNotRunning }
        _ = try await send({ Self.makeCommandEvent(Code.play, processIdentifier: $0) }, to: pid)
    }

    @MainActor
    func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
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
