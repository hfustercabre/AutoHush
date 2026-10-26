import AppKit
import Foundation
import AutoHushKit

/// What a player sends its Apple events through: `AppleEventChannel`, or a
/// stand-in in tests.
package protocol AppleEventSending: Sendable {
    /// The running app's pid; `nil` while it isn't running.
    func processIdentifier() -> pid_t?
    /// The running app's pid, for commands that can't do without it.
    func runningProcessIdentifier() throws -> pid_t
    /// Asks for consent to control the app, showing macOS's prompt if needed.
    func requestPermission(pid: pid_t) async throws
    /// Sends the event `makeEvent` builds for `pid`; the reply's direct object.
    func send(_ makeEvent: @escaping @Sendable (pid_t) -> NSAppleEventDescriptor, to pid: pid_t) async throws -> PlayerReply
}

/// Sends Apple events to one app, with raw Apple events instead of
/// NSAppleScript.
///
/// NSAppleScript is main-thread only: run on a background queue it pumps an
/// event loop while waiting for the reply, which can trap inside BoardServices.
/// `NSAppleEventDescriptor.sendEvent(options:timeout:)` is built on
/// `AESendMessage`, which blocks without running an event loop and is safe on
/// any thread. The sends run on a serial queue of their own, so they neither
/// occupy the cooperative thread pool nor overtake one another.
package final class AppleEventChannel: AppleEventSending {
    let bundleID: String
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
        NSRunningApplication.running(bundleID)?.processIdentifier
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
            throw ScriptablePlayer.mapError(number: Int(status))
        }
    }

    /// macOS installs its standard Apple event coercions on a process's
    /// first coercion, and that isn't safe from several threads at once:
    /// the tests' helper crashed there when tests made their first together
    /// (2026-10-25: five threads in `typeCodeValue`, two inside the install,
    /// one out of stack). Each channel reads its replies on its own queue,
    /// so two players' first replies could race: the first send of any
    /// channel installs them, once, and the others wait for it. As the
    /// tests do (`AppleEventCoercions`).
    private static let coercionsInstalled: Void = {
        _ = NSAppleEventDescriptor(typeCode: fourCharCode("prop")).typeCodeValue
        _ = NSAppleEventDescriptor(int32: 1).coerce(toDescriptorType: typeUnicodeText)?.stringValue
    }()

    /// Builds the event on the queue (descriptors are not Sendable), sends it
    /// and returns the direct object of the reply as a Sendable value.
    package func send(
        _ makeEvent: @escaping @Sendable (pid_t) -> NSAppleEventDescriptor,
        to pid: pid_t
    ) async throws -> PlayerReply {
        try await queue.runThrowing {
            _ = Self.coercionsInstalled
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
