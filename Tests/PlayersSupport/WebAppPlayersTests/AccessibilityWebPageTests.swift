import AppKit
import Testing
import AutoHushKit
@testable import WebAppPlayers

/// The real page reader's parts that need no page: Player Check reads pages with them too.
@Suite("AccessibilityWebPage")
struct AccessibilityWebPageTests {
    /// No process has this number: nothing of it answers.
    private let nobody: pid_t = .max - 1

    @Test("a switch is set on the app itself, or on a Chromium web app's browser while that runs")
    func switchTarget() {
        #expect(AccessibilityWebPage.switchTarget(4242, access: .webKit) == 4242)
        let notRunning = PageAccess(interface: .chromiumWebApp(browserID: "com.example.no-such-browser"), switchAttribute: nil)
        #expect(AccessibilityWebPage.switchTarget(4242, access: notRunning) == 4242)
        // Finder stands in for a browser that runs.
        if let finder = NSRunningApplication.running("com.apple.finder") {
            let running = PageAccess(interface: .chromiumWebApp(browserID: "com.apple.finder"), switchAttribute: nil)
            #expect(AccessibilityWebPage.switchTarget(4242, access: running) == finder.processIdentifier)
        }
    }

    @Test("an app's windows on this desktop, else those found elsewhere, said to be elsewhere")
    func windows() {
        let elsewhere = AXUIElement.application(getpid(), timeout: 1)
        let found = AccessibilityWebPage.windows(of: nobody) { _ in [elsewhere] }
        #expect(found.windows.count == 1 && !found.onThisDesktop)
        #expect(AccessibilityWebPage.windows(of: nobody) { _ in nil }.windows.isEmpty)
    }

    @Test("no player bar around an element with nothing around it")
    func noPlayerBar() {
        #expect(AccessibilityWebPage.playerBar(around: AXUIElement.application(nobody, timeout: 0.5)) == nil)
    }
}
