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

    @Test("not looking late, no look is made once the time is up: its last pause comes after its last look")
    func notLookingLate() {
        var looks = 0
        #expect(Polling.wait(seconds: 1, every: 0.01, lookingLate: false) { looks += 1; return looks == 3 })
        let start = Date()
        var lastLook = start
        #expect(!Polling.wait(seconds: 0.1, every: 0.04, lookingLate: false) { lastLook = Date(); return false })
        let end = Date()
        #expect(end.timeIntervalSince(start) >= 0.1)
        #expect(end.timeIntervalSince(lastLook) >= 0.04)
    }

    @Test("from a first look already made, what holds of it, or no time left, ends the wait unread")
    func fromAFirstLook() {
        var reads = 0
        #expect(Polling.wait(seconds: 5, every: 1, from: 3, reading: { reads += 1; return 0 }, until: { $0 == 3 }) == 3)
        #expect(Polling.wait(seconds: 0, every: 1, from: 1, reading: { reads += 1; return 3 }, until: { $0 == 3 }) == 1)
        #expect(reads == 0)
    }

    @Test("from a first look that doesn't hold, it waits an interval before reading again")
    func fromAFirstLookWaits() {
        let start = Date()
        var firstRead: Date?
        #expect(Polling.wait(seconds: 1, every: 0.1, from: 0, reading: { firstRead = firstRead ?? Date(); return 1 }, until: { $0 == 1 }) == 1)
        #expect(firstRead.map { $0.timeIntervalSince(start) >= 0.1 } == true)
    }

    @Test("with the run loop, what's due on it runs between looks")
    func runsTheRunLoop() {
        let ran = Locked(false)
        RunLoop.current.perform { ran.value = true }
        #expect(Polling.wait(seconds: 2, every: 0.01, runLoop: true) { ran.value })
    }
}
