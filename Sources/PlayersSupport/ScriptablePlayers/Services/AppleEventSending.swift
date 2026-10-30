import Foundation

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
