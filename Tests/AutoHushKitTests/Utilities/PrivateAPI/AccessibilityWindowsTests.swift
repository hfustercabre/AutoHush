import Foundation
import Testing
@testable import AutoHushKit

@Suite("AccessibilityWindows")
struct AccessibilityWindowsTests {
    /// Runs the search over windows at `numbers`, recording every number tried.
    private func search(
        windowsAt numbers: Set<UInt64>, outOfSight: Bool = true, farStart: UInt64? = nil, deadline: Date = .distantFuture,
        now: () -> Date = Date.init
    ) -> (found: [UInt64], tried: [UInt64], askedOutOfSight: Bool) {
        var tried: [UInt64] = []
        var asked = false
        let found = AccessibilityWindows.windowNumbers(
            farStart: farStart,
            hasWindowOutOfSight: { asked = true; return outOfSight },
            deadline: deadline,
            now: now
        ) { number in
            tried.append(number)
            return numbers.contains(number)
        }
        return (found, tried, asked)
    }

    @Test("windows below the usual limit are found there, and nothing above is tried")
    func usualWindows() {
        let result = search(windowsAt: [42, 44, 46])
        #expect(result.found == [42, 44, 46])
        #expect(result.tried.max() == AccessibilityWindows.elementLimit - 1)
        #expect(!result.askedOutOfSight)
    }

    @Test("with none below and no window out of sight, nothing above is tried")
    func noWindowAnywhere() {
        let result = search(windowsAt: [1189], outOfSight: false)
        #expect(result.found.isEmpty)
        #expect(result.askedOutOfSight)
        #expect(result.tried.max() == AccessibilityWindows.elementLimit - 1)
    }

    @Test("with none below and one out of sight, the numbers above are tried: Deezer's window made again")
    func windowMadeAgain() {
        #expect(search(windowsAt: [1189]).found == [1189])
        #expect(search(windowsAt: [2353, 2355]).found == [2353, 2355])
    }

    @Test("above the usual limit, the search ends a gap past the last window found")
    func endsPastLastWindow() {
        let gap = AccessibilityWindows.gapAfterWindow
        let result = search(windowsAt: [1500, 1500 + gap + 1])
        #expect(result.found == [1500])
        #expect(result.tried.max() == 1500 + gap)
    }

    @Test("a later search starts where a window was found before, as numbers only grow; not in a later process given the pid")
    func startsWhereFoundBefore() {
        let result = search(windowsAt: [5200], farStart: 5000)
        #expect(result.found == [5200])
        #expect(!result.tried.contains { (AccessibilityWindows.elementLimit..<5000).contains($0) })

        // Deezer's window #2353 found; then macOS gives its pid to a later
        // process, whose own window is #1189: searched for from the limit.
        let kept = AccessibilityWindows.FarStart(processStart: 1_000, number: 2353)
        #expect(kept.number(inProcessStartedAt: 1_000) == 2353)
        let later = kept.number(inProcessStartedAt: 5_000)
        #expect(later == nil)
        #expect(search(windowsAt: [1189], farStart: later).found == [1189])
        let started = AccessibilityWindows.startTime(of: getpid())
        #expect(started != nil && started == AccessibilityWindows.startTime(of: getpid()))
        #expect(AccessibilityWindows.startTime(of: 999_999) == nil) // above macOS's pids: no process
    }

    @Test("the numbers above stop at the far limit")
    func farLimit() {
        let result = search(windowsAt: [AccessibilityWindows.farLimit + 5])
        #expect(result.found.isEmpty)
        #expect(result.tried.max() == AccessibilityWindows.farLimit - 1)
    }

    @Test("the search stops at its deadline: in the numbers above, or already below, asking nothing more")
    func deadline() {
        // A clock that moves a millisecond each time it's read: once for
        // each number, and once before going above.
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var ticks = 0
        let clock: () -> Date = { ticks += 1; return start.addingTimeInterval(Double(ticks) / 1000) }
        let above = search(windowsAt: [], deadline: start.addingTimeInterval(1.5), now: clock)
        #expect(above.found.isEmpty)
        #expect(above.tried.last == 1497)

        ticks = 0
        let below = search(windowsAt: [], deadline: start.addingTimeInterval(0.5), now: clock)
        #expect(below.tried.last == 498)
        #expect(!below.askedOutOfSight)
    }
}
