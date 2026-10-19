import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("Polling")
struct PollingTests {
    @Test("what holds at the first look returns at once")
    func holdsAtOnce() {
        var looks = 0
        let start = Date()
        #expect(Polling.wait(seconds: 5, every: 1) { looks += 1; return true })
        #expect(looks == 1 && Date().timeIntervalSince(start) < 0.5)
    }

    @Test("it reads until what it read holds, and returns that")
    func readsUntilItHolds() {
        var reads = 0
        #expect(Polling.wait(seconds: 5, every: 0.01, reading: { reads += 1; return reads }, until: { $0 == 3 }) == 3)
    }

    @Test("what never holds is false once the time is up, its last look made then")
    func timeUp() {
        let start = Date()
        var lastLook = start
        #expect(!Polling.wait(seconds: 0.1, every: 0.02) { lastLook = Date(); return false })
        #expect(lastLook.timeIntervalSince(start) >= 0.09)
    }

    @Test("not looking first, it waits an interval before its first look")
    func waitsFirst() {
        let start = Date()
        var firstLook: Date?
        #expect(Polling.wait(seconds: 1, every: 0.1, lookingFirst: false) { firstLook = firstLook ?? Date(); return true })
        #expect(firstLook.map { $0.timeIntervalSince(start) >= 0.1 } == true)
    }

    @Test("with the run loop, what's due on it runs between looks")
    func runsTheRunLoop() {
        let ran = Locked(false)
        RunLoop.current.perform { ran.value = true }
        #expect(Polling.wait(seconds: 2, every: 0.01, runLoop: true) { ran.value })
    }
}
