import AppKit
import Foundation
import AutoHushKit

/// Sends Apple events to one app, with raw Apple events instead of
/// NSAppleScript.
///
/// NSAppleScript is main-thread only: run on a background queue it pumps an
/// event loop while waiting for the reply, which can trap inside BoardServices.
/// `NSAppleEventDescriptor.sendEvent(options:timeout:)` is built on
/// `AESendMessage`, which blocks without running an event loop and is safe on
/// any thread. The sends run on a serial queue of their own, so they neither
/// occupy the cooperative thread pool nor overtake one another.
package final class AppleEventChannel: Sendable {
    package let bundleID: String
    private let queue: DispatchQueue

    /// How long to wait for the app to answer an event.
    package static let replyTimeout: TimeInterval = 5

    package init(bundleID: String, label: String) {
        self.bundleID = bundleID
        queue = DispatchQueue(label: "AutoHush.\(label)", qos: .userInitiated)
    }

    /// The running app's pid. Targeting the running process (rather than the
    /// bundle ID) guarantees that an event can never launch the app.
    package func processIdentifier() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { !$0.isTerminated }?
            .processIdentifier
    }

    /// The running app's pid, for commands that can't do without it.
    package func runningProcessIdentifier() throws -> pid_t {
        guard let pid = processIdentifier() else { throw MusicPlayerError.playerNotRunning }
        return pid
    }

    /// Asks for consent to control the app up front: a send times out after a
    /// few seconds, which is too short for a user reading the TCC prompt.
    package func requestPermission(pid: pid_t) async throws {
        let status = await queue.run { AutomationPermission.check(pid: pid, ask: true) }
        if status != noErr {
            throw ScriptablePlayer.mapError(number: Int(status), message: nil)
        }
    }

    /// Builds the event on the queue (descriptors are not Sendable), sends it
    /// and returns the direct object of the reply as a Sendable value.
    package func send(
        _ makeEvent: @escaping @Sendable (pid_t) -> NSAppleEventDescriptor,
        to pid: pid_t
    ) async throws -> PlayerReply {
        try await queue.runThrowing {
            let event = makeEvent(pid)
            let reply: NSAppleEventDescriptor
            do {
                reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: Self.replyTimeout)
            } catch {
                throw ScriptablePlayer.mapError(error)
            }
            if let error = ScriptablePlayer.replyError(reply) { throw error }
            return PlayerReply(reply)
        }
    }
}
