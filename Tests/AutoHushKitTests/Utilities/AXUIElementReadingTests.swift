import ApplicationServices
import Foundation
import Testing
@testable import AutoHushKit

@Suite("AXUIElement+Reading")
struct AXUIElementReadingTests {
    @Test("an app's element is its process's, and reads of one that isn't there come back empty at once")
    func application() {
        var pid: pid_t = 0
        let own = AXUIElement.application(getpid(), timeout: 0.5)
        #expect(AXUIElementGetPid(own, &pid) == .success && pid == getpid())
        #expect(own.waiting(0.25) === own)
        // No process 2³¹-2: nothing to wait for.
        let gone = AXUIElement.application(.max - 1, timeout: 0.5)
        let start = Date()
        #expect(gone.children(timeout: 0.5).isEmpty)
        #expect(gone.elements(kAXWindowsAttribute, timeout: 0.5).isEmpty)
        #expect(gone.element(kAXMenuBarAttribute, timeout: 0.5) == nil)
        #expect(gone.frame == nil)
        #expect(Date().timeIntervalSince(start) < 3)
    }
}
