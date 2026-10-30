import AppKit
import Testing
import ScriptablePlayers

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
