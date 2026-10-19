import CoreAudio
import Foundation
import os
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

/// Each test has preferences of its own, removed after it.
@Suite("SystemVolumeLeveler")
final class SystemVolumeLevelerTests {
    private let suite = TestDefaults("SystemVolumeLevelerTests")
    private let defaults: UserDefaults

    init() { defaults = suite.defaults }
    deinit { suite.remove() }

    /// A leveler of `volume`, with this test's preferences: its glide back
    /// up steps at once, unless `sleep` waits.
    private func leveler(_ volume: any SystemVolumeControlling, sleep: @escaping @Sendable (TimeInterval) -> Void = { _ in },
                         now: @escaping @Sendable () -> Date = Date.init) -> SystemVolumeLeveler {
        SystemVolumeLeveler(volume: volume, defaults: defaults, sleep: sleep, now: now)
    }

    /// What it lowered is kept for the next launch.
    private var isKept: Bool { defaults.data(forKey: SystemVolumeLeveler.leftKey) != nil }

    @Test("lowers each channel by as much, never below the lowest, and puts it back over the fade-out in steps")
    func lowersAndRestores() async throws {
        let volume = MockSystemVolume([1: -12, 2: -14], lowest: -20)
        let leveler = leveler(volume)
        let token = try #require(leveler.lower(by: -6))
        #expect(volume.decibels == [1: -18, 2: -20]) // the balance kept, -20 the lowest
        #expect(leveler.lower(by: -3) == nil) // already lowered: once only
        #expect(volume.decibels == [1: -18, 2: -20])

        leveler.restore(over: 0.2, lowered: token)
        await TestWait.until { !self.isKept } // back: nothing kept
        #expect(volume.decibels == [1: -12, 2: -14])
        #expect(volume.sets.count == 1 + 4) // lowered, then 4 steps of 50 ms
        #expect(volume.sets[1] == [1: -16.5, 2: -18.5])
    }

    @Test("the user's own change wins: a volume changed meanwhile is left as it is, at once or over the fade-out")
    func userChangeWins() throws {
        let volume = MockSystemVolume([0: -10])
        let leveler = leveler(volume)
        let token = try #require(leveler.lower(by: -8))
        volume.decibels = [0: -25] // the volume keys
        leveler.restoreNow(lowered: token)
        #expect(volume.decibels == [0: -25] && !isKept)

        volume.decibels = [0: -10]
        let again = try #require(leveler.lower(by: -8))
        volume.decibels = [0: -14] // the volume keys, before the music pauses again
        leveler.restore(over: 0.2, lowered: again)
        #expect(volume.decibels == [0: -14] && !isKept) // no glide: nothing more set
        #expect(volume.sets == [[0: -18], [0: -18]])
    }

    @Test("the glide back up stops once the user changes the volume during it, and leaves it as they set it")
    func glideYieldsToTheUser() async throws {
        let volume = MockSystemVolume([0: -10])
        let steps = OSAllocatedUnfairLock(initialState: 0)
        let leveler = leveler(volume, sleep: { _ in
            // The volume keys, after the glide's first step.
            if steps.withLock({ $0 += 1; return $0 }) == 1 { volume.decibels = [0: -30] }
        })
        let token = try #require(leveler.lower(by: -8))
        leveler.restore(over: 0.2, lowered: token) // 4 steps: -16, -14, -12, -10
        await TestWait.until { !self.isKept }
        #expect(volume.decibels == [0: -30])
        #expect(volume.sets == [[0: -18], [0: -16]])
    }

    @Test("a glide whose output is unplugged midway stops and forgets it; the next resume lowers the output there then")
    func glideOutputUnplugged() async throws {
        let volume = MockSystemVolume([0: -10])
        let steps = OSAllocatedUnfairLock(initialState: 0)
        let leveler = leveler(volume, sleep: { _ in
            if steps.withLock({ $0 += 1; return $0 }) == 1 { volume.isPlugged = false } // headphones out
        })
        let token = try #require(leveler.lower(by: -8))
        leveler.restore(over: 0.2, lowered: token)
        await TestWait.until { !self.isKept }
        #expect(volume.sets == [[0: -18], [0: -16]])

        volume.isPlugged = true
        #expect(leveler.lower(by: -6) != nil) // not left gliding
        #expect(volume.decibels == [0: -22])
    }

    @Test("an output with no volume control is left alone, and so is a restore with nothing lowered")
    func noControl() {
        let volume = MockSystemVolume(nil)
        let leveler = leveler(volume)
        #expect(leveler.lower(by: -8) == nil)
        leveler.restoreNow()
        #expect(volume.sets.isEmpty)
    }

    @Test("one leveler for every monitoring: only the lowering's own token puts it back; a put-back for all (a quit, the setting off) puts back whatever is lowered")
    func onlyItsOwnToken() throws {
        let volume = MockSystemVolume([0: -10])
        let leveler = leveler(volume)
        let token = try #require(leveler.lower(by: -8))
        let another = UUID() // a monitoring that lowered nothing now
        leveler.restore(over: 0.2, lowered: another)
        leveler.restoreNow(lowered: another)
        #expect(volume.decibels == [0: -18] && isKept)
        leveler.restoreNow(lowered: token)
        #expect(volume.decibels == [0: -10] && !isKept)
        leveler.restoreNow(lowered: token) // put back already: nothing more
        #expect(volume.sets.count == 2)

        _ = try #require(leveler.lower(by: -8))
        leveler.restoreNow()
        #expect(volume.decibels == [0: -10] && !isKept)
    }

    @Test("what it lowered is kept until it's put back: after a quit or a crash, the next launch puts it back, unless the user changed it since")
    func putBackAtLaunch() {
        let volume = MockSystemVolume([0: -10])
        func launch() -> SystemVolumeLeveler { leveler(volume) }
        launch().lower(by: -8) // AutoHush quits or crashes with the music lowered
        #expect(volume.decibels == [0: -18])
        launch().restoreIfLeft()
        #expect(volume.decibels == [0: -10])
        launch().restoreIfLeft() // nothing left: nothing changes
        #expect(volume.sets.count == 2)

        launch().lower(by: -8)
        volume.decibels = [0: -30] // the volume keys, before the next launch
        launch().restoreIfLeft()
        #expect(volume.decibels == [0: -30])
        #expect(!isKept) // forgotten
    }

    @Test("at launch, only a volume lowered within the hour is put back; one lowered longer ago is the user's, and forgotten; a record from before it was dated is put back")
    func onlyRecentAtLaunch() throws {
        let volume = MockSystemVolume([0: -10])
        let start = Date(timeIntervalSince1970: 1_000_000)
        leveler(volume, now: { start }).lower(by: -8)
        leveler(volume, now: { start + SystemVolumeLeveler.maxAge - 60 }).restoreIfLeft()
        #expect(volume.decibels == [0: -10])

        leveler(volume, now: { start }).lower(by: -8)
        leveler(volume, now: { start + SystemVolumeLeveler.maxAge + 60 }).restoreIfLeft()
        #expect(volume.decibels == [0: -18] && !isKept)

        // As the leveler kept it before 2026-10-18: no token, no date.
        struct Undated: Codable {
            let uid: String
            let original: [AudioObjectPropertyElement: Float]
            let lowered: [AudioObjectPropertyElement: Float]
        }
        let undated = try JSONEncoder().encode(Undated(uid: "Speakers", original: [0: -10], lowered: [0: -18]))
        defaults.set(undated, forKey: SystemVolumeLeveler.leftKey)
        leveler(volume).restoreIfLeft()
        #expect(volume.decibels == [0: -10] && !isKept)
    }

    @Test("nothing waits for the glide back up: a put-back at once, or a resume lowering again, stops it where it is")
    func glideStops() throws {
        let volume = MockSystemVolume([0: -10])
        // Each step of the glide waits here, until the test lets it go on.
        let stepped = DispatchSemaphore(value: 0), goOn = DispatchSemaphore(value: 0)
        let timedOut = OSAllocatedUnfairLock(initialState: false)
        let leveler = leveler(volume, sleep: { _ in
            stepped.signal()
            if goOn.wait(timeout: TestWait.dispatchDeadline) == .timedOut { timedOut.withLock { $0 = true } }
        })
        let token = try #require(leveler.lower(by: -8))
        leveler.restore(over: 0.2, lowered: token) // 4 steps: -16, -14, -12, -10
        #expect(stepped.wait(timeout: TestWait.dispatchDeadline) == .success)
        #expect(volume.decibels == [0: -16])

        // The music resumes again: from the volume it was going back to.
        let again = try #require(leveler.lower(by: -6))
        #expect(volume.decibels == [0: -16])
        goOn.signal() // the old glide wakes, stopped

        // The next one, after it on its queue: it set nothing more meanwhile.
        leveler.restore(over: 0.2, lowered: again)
        #expect(stepped.wait(timeout: TestWait.dispatchDeadline) == .success)
        #expect(volume.sets == [[0: -18], [0: -16], [0: -10], [0: -16], [0: -14.5]])

        // Settings or a stop: at once, while the glide waits.
        leveler.restoreNow()
        #expect(volume.decibels == [0: -10] && !isKept)
        goOn.signal()
        #expect(!timedOut.withLock { $0 })
    }

    @Test("a put-back at once during the glide back up leaves a volume the user changed since its last step as they set it")
    func putBackDuringGlideYieldsToTheUser() throws {
        let volume = MockSystemVolume([0: -10])
        let stepped = DispatchSemaphore(value: 0), goOn = DispatchSemaphore(value: 0)
        let leveler = leveler(volume, sleep: { _ in
            stepped.signal()
            _ = goOn.wait(timeout: TestWait.dispatchDeadline)
        })
        let token = try #require(leveler.lower(by: -8))
        leveler.restore(over: 0.2, lowered: token) // 4 steps: -16, -14, -12, -10
        #expect(stepped.wait(timeout: TestWait.dispatchDeadline) == .success)
        volume.decibels = [0: -30] // the volume keys, between two steps

        leveler.restoreNow(lowered: token) // the music resumes, or its monitoring stops
        #expect(volume.decibels == [0: -30] && !isKept)
        goOn.signal()
        #expect(volume.sets == [[0: -18], [0: -16]])
    }

    @Test("with sound moved to another output meanwhile, the output it lowered is put back, found by its UID, at once or over the fade-out; the other is left alone")
    func putsBackTheOutputItLowered() async throws {
        let outputs = TwoOutputs()
        let leveler = leveler(outputs)
        let token = try #require(leveler.lower(by: -6))
        #expect(outputs.decibels == [42: [0: -16], 43: [0: -20]])
        outputs.current = 43 // headphones plugged in
        leveler.restoreNow(lowered: token)
        #expect(outputs.decibels == [42: [0: -10], 43: [0: -20]])

        let again = try #require(leveler.lower(by: -6)) // the headphones, now
        #expect(outputs.decibels[43] == [0: -26])
        outputs.current = 42 // unplugged
        leveler.restore(over: 0.2, lowered: again)
        await TestWait.until { !self.isKept }
        #expect(outputs.decibels == [42: [0: -10], 43: [0: -20]])
        #expect(outputs.sets.map(\.device) == [42, 42, 43, 43, 43, 43, 43])
    }
}

/// Two outputs, each with its own volume, in memory: the speakers (42) and
/// headphones (43); sound plays through `current`.
private final class TwoOutputs: SystemVolumeControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var _current: AudioObjectID = 42
    private var _decibels: [AudioObjectID: [AudioObjectPropertyElement: Float]] = [42: [0: -10], 43: [0: -20]]
    private var _sets: [(device: AudioObjectID, decibels: [AudioObjectPropertyElement: Float])] = []
    private let uids: [AudioObjectID: String] = [42: "Speakers", 43: "Headphones"]

    var current: AudioObjectID {
        get { lock.withLock { _current } }
        set { lock.withLock { _current = newValue } }
    }

    var decibels: [AudioObjectID: [AudioObjectPropertyElement: Float]] { lock.withLock { _decibels } }

    /// Each volume set, in turn, with its output.
    var sets: [(device: AudioObjectID, decibels: [AudioObjectPropertyElement: Float])] { lock.withLock { _sets } }

    func defaultOutput() -> AudioObjectID? { current }
    func uid(of device: AudioObjectID) -> String? { uids[device] }
    func device(withUID uid: String) -> AudioObjectID? { uids.first { $0.value == uid }?.key }

    func volume(of device: AudioObjectID) -> SystemVolume? {
        lock.withLock { _decibels[device].map { SystemVolume(decibels: $0, lowest: -60) } }
    }

    func setDecibels(_ decibels: [AudioObjectPropertyElement: Float], of device: AudioObjectID) {
        lock.withLock {
            _decibels[device] = decibels
            _sets.append((device, decibels))
        }
    }
}
