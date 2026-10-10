import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("SourceActivityTracker")
struct SourceActivityTrackerTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    /// Keeps the mutating call out of `#expect`, which may re-evaluate its operands.
    private func step(
        _ tracker: inout SourceActivityTracker, audible: Set<String>, at date: Date
    ) -> (started: Set<String>, stopped: Set<String>) {
        tracker.update(audible: audible, at: date)
    }

    private func makeTracker() -> SourceActivityTracker {
        SourceActivityTracker(startConfirmation: 1.0, gapTolerance: 0.5, stopGrace: 2.0)
    }

    @Test("starts a source once it has been audible for the confirmation time")
    func startsAfterConfirmation() {
        var tracker = makeTracker()
        #expect(step(&tracker, audible: ["a"], at: t0).started.isEmpty)
        #expect(step(&tracker, audible: ["a"], at: t0 + 0.75).started.isEmpty)
        #expect(step(&tracker, audible: ["a"], at: t0 + 1.0).started == ["a"])
        #expect(tracker.activeSources == ["a"])
    }

    @Test("gaps within the tolerance do not restart the confirmation")
    func toleratesShortGaps() {
        var tracker = makeTracker()
        _ = tracker.update(audible: ["a"], at: t0)
        _ = tracker.update(audible: [], at: t0 + 0.25)
        #expect(step(&tracker, audible: ["a"], at: t0 + 0.5).started.isEmpty)
        #expect(step(&tracker, audible: ["a"], at: t0 + 1.0).started == ["a"])
    }

    @Test("observed silence longer than the tolerance restarts the confirmation")
    func longGapRestartsConfirmation() {
        var tracker = makeTracker()
        _ = tracker.update(audible: ["a"], at: t0)
        _ = tracker.update(audible: [], at: t0 + 0.6)
        #expect(step(&tracker, audible: ["a"], at: t0 + 1.0).started.isEmpty)
        #expect(step(&tracker, audible: ["a"], at: t0 + 1.5).started.isEmpty)
        #expect(step(&tracker, audible: ["a"], at: t0 + 2.0).started == ["a"])
    }

    @Test("a delayed evaluation does not restart the confirmation")
    func delayedEvaluationKeepsConfirmation() {
        var tracker = makeTracker()
        _ = tracker.update(audible: ["a"], at: t0)
        #expect(step(&tracker, audible: ["a"], at: t0 + 1.0).started == ["a"])
    }

    @Test("an unconfirmed source is forgotten after the gap tolerance")
    func pendingSourceIsDropped() {
        var tracker = makeTracker()
        _ = tracker.update(audible: ["a"], at: t0)
        _ = tracker.update(audible: [], at: t0 + 0.6)
        #expect(tracker.isIdle)
    }

    @Test("stops an active source only after the grace period")
    func stopsAfterGrace() {
        var tracker = makeTracker()
        _ = tracker.update(audible: ["a"], at: t0)
        _ = tracker.update(audible: ["a"], at: t0 + 1.0)
        #expect(step(&tracker, audible: [], at: t0 + 2.5).stopped.isEmpty)
        #expect(step(&tracker, audible: [], at: t0 + 3.0).stopped == ["a"])
        #expect(tracker.isIdle)
    }

    @Test("sound during the grace period keeps the source active")
    func soundDuringGraceKeepsSource() {
        var tracker = makeTracker()
        _ = tracker.update(audible: ["a"], at: t0)
        _ = tracker.update(audible: ["a"], at: t0 + 1.0)
        _ = tracker.update(audible: [], at: t0 + 2.5)
        let result = tracker.update(audible: ["a"], at: t0 + 2.9)
        #expect(result.started.isEmpty && result.stopped.isEmpty)
        #expect(step(&tracker, audible: [], at: t0 + 4.8).stopped.isEmpty)
        #expect(step(&tracker, audible: [], at: t0 + 4.9).stopped == ["a"])
    }

    @Test("zero hysteresis reproduces instant start and stop")
    func zeroHysteresisIsInstant() {
        var tracker = SourceActivityTracker(startConfirmation: 0, gapTolerance: 0, stopGrace: 0)
        #expect(step(&tracker, audible: ["a"], at: t0).started == ["a"])
        #expect(step(&tracker, audible: [], at: t0 + 0.01).stopped == ["a"])
    }

    @Test("tracks sources independently")
    func independentSources() {
        var tracker = makeTracker()
        _ = tracker.update(audible: ["a"], at: t0)
        _ = tracker.update(audible: ["a", "b"], at: t0 + 0.5)
        #expect(step(&tracker, audible: ["a", "b"], at: t0 + 1.0).started == ["a"])
        #expect(step(&tracker, audible: ["a", "b"], at: t0 + 1.5).started == ["b"])
        #expect(tracker.activeSources == ["a", "b"])
    }

    @Test("remembers when a source was first heard, through its start, until it's forgotten")
    func remembersFirstHeard() {
        var tracker = makeTracker()
        #expect(tracker.firstHeard("a") == nil)
        _ = step(&tracker, audible: ["a"], at: t0)
        _ = step(&tracker, audible: [], at: t0 + 0.75) // a gap past the tolerance: forgotten
        #expect(tracker.firstHeard("a") == nil)
        _ = step(&tracker, audible: ["a"], at: t0 + 1)
        #expect(step(&tracker, audible: ["a"], at: t0 + 2).started == ["a"])
        #expect(tracker.firstHeard("a") == t0 + 1)
        _ = step(&tracker, audible: [], at: t0 + 3)
        #expect(step(&tracker, audible: [], at: t0 + 4).stopped == ["a"])
        #expect(tracker.firstHeard("a") == nil)
    }

    @Test("a source can be given its own start confirmation, e.g. a longer one")
    func ownStartConfirmation() {
        var tracker = makeTracker()
        let longer = ["b": 3.0]
        _ = tracker.update(audible: ["a", "b"], at: t0, startConfirmations: longer)
        #expect(tracker.update(audible: ["a", "b"], at: t0 + 1.0, startConfirmations: longer).started == ["a"])
        #expect(tracker.update(audible: ["a", "b"], at: t0 + 2.75, startConfirmations: longer).started.isEmpty)
        #expect(tracker.update(audible: ["a", "b"], at: t0 + 3.0, startConfirmations: longer).started == ["b"])

        // The usual confirmation applies again once a source no longer needs a longer one.
        _ = tracker.update(audible: ["c"], at: t0 + 10, startConfirmations: ["c": 3])
        #expect(tracker.update(audible: ["c"], at: t0 + 11).started == ["c"])
    }

    @Test("reset forgets every source")
    func resetForgetsSources() {
        var tracker = makeTracker()
        _ = tracker.update(audible: ["a"], at: t0)
        _ = tracker.update(audible: ["a"], at: t0 + 1.0)
        tracker.reset()
        #expect(tracker.isIdle)
        #expect(tracker.activeSources.isEmpty)
    }
}
