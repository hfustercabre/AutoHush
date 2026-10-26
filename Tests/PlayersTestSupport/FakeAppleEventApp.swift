import AppKit
import Testing
import os
import AutoHushKit
import ScriptablePlayers

/// What a scripted app's fake keeps: its process (`nil` while it isn't
/// running), and what it was sent, in order ("ask" for its consent).
package protocol AppleEventAppState: Sendable {
    var pid: pid_t? { get }
    var sent: [String] { get set }
}

/// An app scripted with Apple events, without the app: its process, its
/// consent asked, and what it was sent. Each fake answers its own events
/// (`send`), reading them with `SentEvent`; its suites take
/// `.appleEventCoercions`.
package protocol FakeAppleEventApp: AppleEventSending {
    associatedtype State: AppleEventAppState
    var state: OSAllocatedUnfairLock<State> { get }
}

extension FakeAppleEventApp {
    package var sent: [String] { state.withLock { $0.sent } }

    package func processIdentifier() -> pid_t? { state.withLock { $0.pid } }

    package func runningProcessIdentifier() throws -> pid_t {
        guard let pid = processIdentifier() else { throw MusicPlayerError.playerNotRunning }
        return pid
    }

    package func requestPermission(pid: pid_t) async throws { state.withLock { $0.sent.append("ask") } }
}

/// What an Apple event asks, read before a fake's lock: descriptors aren't
/// Sendable.
package struct SentEvent {
    /// Its class and ID, as text: "coregetd", "jukePaus".
    package let code: String
    /// Its direct object (`----`).
    package let direct: NSAppleEventDescriptor?
    /// The property it reads or sets (its direct object's `seld`).
    package let property: OSType?
    /// The value it sets (`data`), as a number.
    package let value: Int?

    package init(_ event: NSAppleEventDescriptor) {
        code = Self.text(event.eventClass) + Self.text(event.eventID)
        direct = event.paramDescriptor(forKeyword: fourCharCode("----"))
        property = direct?.forKeyword(fourCharCode("seld"))?.typeCodeValue
        value = event.paramDescriptor(forKeyword: fourCharCode("data")).map { Int($0.int32Value) }
    }

    /// A four-char code as its text ("jukePaus" is "juke" and "Paus").
    package static func text(_ code: OSType) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }, encoding: .macOSRoman) ?? "?"
    }
}

/// macOS installs its standard Apple event coercions on a process's first
/// coercion, and that isn't safe from several threads at once: parallel
/// tests making their first together crashed the test helper there
/// (2026-10-25: five threads in `typeCodeValue`, one out of stack in the
/// install). A suite that reads Apple events takes this trait: it installs
/// them before the suite's tests, once, while any other such suite waits.
package struct AppleEventCoercions: SuiteTrait, TestScoping {
    @concurrent
    package func provideScope(for test: Test, testCase: Test.Case?,
                              performing function: @Sendable @concurrent () async throws -> Void) async throws {
        _ = Self.installed
        try await function()
    }

    private static let installed: Void = {
        _ = NSAppleEventDescriptor(typeCode: fourCharCode("prop")).typeCodeValue
        _ = NSAppleEventDescriptor(int32: 1).coerce(toDescriptorType: typeUnicodeText)?.stringValue
    }()
}

extension Trait where Self == AppleEventCoercions {
    /// Apple event coercions installed before the suite's tests start.
    package static var appleEventCoercions: Self { Self() }
}
