import Foundation
import Testing
@testable import AutoHushApp
import AutoHushTestSupport

@Suite("WindowWatch", .timeLimit(.minutes(1)))
@MainActor
struct WindowWatchTests {
    /// A window the watch follows, opened or closed by the test.
    @MainActor
    private final class Window {
        var isOpen = true
        var needs: Set<WindowWatch.Refresh>
        init(needs: Set<WindowWatch.Refresh>) { self.needs = needs }
    }

    /// The watch, with a clock the test steps, and what it refreshed and
    /// how many rounds it ended.
    @MainActor
    private final class Bench {
        let clock = ManualSleep()
        var refreshed: [WindowWatch.Refresh] = []
        var ticks = 0
        private(set) var windows: [Window] = []
        lazy var watch = WindowWatch(sleep: clock.sleep,
                                     refresh: { [weak self] in self?.refreshed.append($0) },
                                     everyTick: { [weak self] in self?.ticks += 1 })

        @discardableResult
        func window(needs: Set<WindowWatch.Refresh>) -> Window {
            let window = Window(needs: needs)
            windows.append(window)
            watch.register(isOpen: { [weak window] in window?.isOpen == true }) { [weak window] in window?.needs ?? [] }
            return window
        }

        /// The watch ended a round and waits for the next.
        func asleep(sourceLocation: SourceLocation = #_sourceLocation) async {
            await TestWait.until(sourceLocation: sourceLocation) { self.clock.sleeping == 1 }
        }
    }

    @Test("an open window's needs are refreshed at once, then each second, in their order, each round ending with the tick")
    func refreshesWhileOpen() async {
        let bench = Bench()
        bench.window(needs: [.permissions, .players])
        bench.watch.wake()
        await bench.asleep()
        #expect(bench.refreshed == [.players, .permissions])
        #expect(bench.ticks == 1)

        bench.clock.step()
        await TestWait.until { bench.refreshed.count == 4 }
        await bench.asleep()
        #expect(bench.refreshed == [.players, .permissions, .players, .permissions])
        #expect(bench.ticks == 2)
    }

    @Test("the open windows' needs are merged, each refresh once a round; a closed window's don't count")
    func mergesOpenWindows() async {
        let bench = Bench()
        bench.window(needs: [.permissions])
        bench.window(needs: [.players, .notifications, .permissions])
        bench.window(needs: [.diagnostics, .launchAtLogin]).isOpen = false
        bench.watch.wake()
        await bench.asleep()
        #expect(bench.refreshed == [.players, .notifications, .permissions])
    }

    @Test("what a window needs is asked each round: Diagnostics once its page shows, say")
    func needsAskedEachRound() async {
        let bench = Bench()
        let settings = bench.window(needs: [.permissions])
        bench.watch.wake()
        await bench.asleep()

        settings.needs = [.diagnostics, .permissions]
        bench.clock.step()
        await TestWait.until { bench.refreshed.count == 3 }
        #expect(bench.refreshed == [.permissions, .diagnostics, .permissions])
    }

    @Test("once no window is open it stops, with one more tick, until a window wakes it again")
    func stopsWithNoWindowOpen() async {
        let bench = Bench()
        let window = bench.window(needs: [.players])
        bench.watch.wake()
        await bench.asleep()

        window.isOpen = false
        bench.clock.step()
        await bench.watch.loopTask?.value // stopped
        #expect(bench.clock.sleeping == 0)
        #expect(bench.refreshed == [.players])
        #expect(bench.ticks == 2)

        window.isOpen = true
        bench.watch.wake()
        await bench.asleep()
        #expect(bench.refreshed == [.players, .players])
    }

    @Test("woken while it runs, it starts over at once, and one loop runs on")
    func oneLoop() async {
        let bench = Bench()
        bench.window(needs: [.permissions])
        bench.watch.wake()
        await bench.asleep()

        let first = bench.watch.loopTask
        bench.watch.wake() // the window opened again, say
        await first?.value // the first loop is over
        await TestWait.until { bench.refreshed.count == 2 }
        await bench.asleep()
        #expect(bench.clock.sleeping == 1)

        bench.clock.step()
        await TestWait.until { bench.refreshed.count == 3 }
        await bench.asleep()
        #expect(bench.refreshed.count == 3)
    }

    @Test("with no window open, waking it refreshes nothing; the tick runs once")
    func nothingOpen() async {
        let bench = Bench()
        bench.window(needs: [.players]).isOpen = false
        bench.watch.wake()
        await TestWait.until { bench.ticks == 1 }
        #expect(bench.refreshed.isEmpty)
        #expect(bench.clock.sleeping == 0)
    }
}
