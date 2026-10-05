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

    package init(
        bundleID: String,
        name: String,
        suite: OSType,
        stateNotification: Notification.Name,
        volumeCurve: VolumeCurve = .linear,
        readVolume: @escaping @Sendable (Int) -> Int = { $0 }
    ) {
        self.bundleID = bundleID
        self.name = name
        self.suite = suite
        self.stateNotification = stateNotification
        self.volumeCurve = volumeCurve
        self.readVolume = readVolume
    }
}

/// Controls a music app with raw Apple events instead of NSAppleScript: its
/// state, pause, play and volume, as described by its profile.
///
/// NSAppleScript is main-thread only: run on a background queue it pumps an
/// event loop while waiting for the reply, which can trap inside BoardServices.
/// `NSAppleEventDescriptor.sendEvent(options:timeout:)` is built on
/// `AESendMessage`, which blocks without running an event loop and is safe on
/// any thread.
package actor ScriptablePlayer: MusicPlayer {
    package nonisolated let profile: ScriptablePlayerProfile

    package nonisolated var bundleID: String { profile.bundleID }
    package nonisolated var name: String { profile.name }
    package nonisolated var volumeCurve: VolumeCurve { profile.volumeCurve }

    private let logger = Logger(category: "ScriptablePlayer")

    /// Serial queue for the blocking sends, so they neither occupy the
    /// cooperative thread pool nor overtake one another.
    private let eventQueue: DispatchQueue

    package init(profile: ScriptablePlayerProfile) {
        self.profile = profile
        eventQueue = DispatchQueue(label: "AutoHush.\(profile.name)", qos: .userInitiated)
    }

    /// How long to wait for the app to answer an event.
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
        guard let pid = processIdentifier() else { return .notRunning }
        do {
            let reply = try await send(Self.makeGetPlayerStateEvent(processIdentifier:), to: pid)
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
        guard let pid = processIdentifier(),
              let reply = try? await send(Self.makeGetVolumeEvent(processIdentifier:), to: pid)
        else { return nil }
        return Self.volume(fromReply: reply, reading: profile.readVolume)
    }

    package func setVolume(_ volume: Int) async throws {
        let volume = min(max(volume, 0), 100)
        let pid = try runningProcessIdentifier()
        _ = try await send({ Self.makeSetVolumeEvent(volume, processIdentifier: $0) }, to: pid)
    }

    @MainActor
    package func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        PlayerStateObserver(notification: profile.stateNotification, bundleID: profile.bundleID, onChange: onChange)
    }

    // MARK: - Private helpers

    /// Targeting the running process (rather than the bundle ID) guarantees
    /// that an event can never launch the app.
    private func processIdentifier() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: profile.bundleID)
            .first { !$0.isTerminated }?
            .processIdentifier
    }

    /// The running app's pid, for commands that can't do without it.
    private func runningProcessIdentifier() throws -> pid_t {
        guard let pid = processIdentifier() else { throw MusicPlayerError.playerNotRunning }
        return pid
    }

    /// Sends a parameterless command of the app's suite, such as pause or play.
    private func sendCommand(_ eventID: AEEventID) async throws {
        let pid = try runningProcessIdentifier()
        let suite = profile.suite
        _ = try await send({ Self.makeCommandEvent(suite: suite, eventID, processIdentifier: $0) }, to: pid)
    }

    /// Builds the event on `eventQueue` (descriptors are not Sendable), sends
    /// it and returns the direct object of the reply as a Sendable value.
    private func send(
        _ makeEvent: @escaping @Sendable (pid_t) -> NSAppleEventDescriptor,
        to pid: pid_t
    ) async throws -> PlayerReply {
        try await onEventQueue {
            let event = makeEvent(pid)
            let reply: NSAppleEventDescriptor
            do {
                reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: Self.replyTimeout)
            } catch {
                throw Self.mapError(error)
            }
            if let error = Self.replyError(reply) { throw error }
            return PlayerReply(reply)
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
