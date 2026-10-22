import AppKit
import Foundation
import Testing
@testable import AutoHushApp
import AutoHushTestSupport

/// When AutoHush's alerts run: after the work that asked for them, never
/// over another alert or panel.
@Suite("InfoAlert")
@MainActor
struct InfoAlertTests {
    @Test("an alert asked for while another is open (its modal loop running) waits until it closes")
    func waitsForOpenOnes() async {
        var shown = 0
        InfoAlert.whenNoneOpen { shown += 1 }
        #expect(shown == 0) // after the work that asked for it
        runAsAnotherAlert()
        #expect(shown == 0)
        await TestWait.until { shown == 1 }
    }

    /// The run loop as another alert's modal loop runs it, for a moment.
    private func runAsAnotherAlert() {
        RunLoop.main.run(mode: .modalPanel, before: Date(timeIntervalSinceNow: 0.05))
    }
}
