import AppKit
import Testing

/// `NSApp` set up before the suite's tests. A suite that needs it (a
/// window's icon, `NSApp.sendAction`, its windows) takes this trait, so it
/// works when it runs alone, with no other suite to set it up first (B3,
/// the full check, 2026-10-27: `NSApp` was nil).
package struct ApplicationSetUp: SuiteTrait, TestScoping {
    @concurrent
    package func provideScope(for test: Test, testCase: Test.Case?,
                              performing function: @Sendable @concurrent () async throws -> Void) async throws {
        await MainActor.run { _ = NSApplication.shared }
        try await function()
    }
}

extension Trait where Self == ApplicationSetUp {
    /// `NSApp` set up before the suite's tests start.
    package static var application: Self { Self() }
}
