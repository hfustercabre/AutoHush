import Foundation
import os
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

/// Bounded: a broken run would otherwise hang the whole test run unnamed.
@Suite("ToolRun", .timeLimit(.minutes(1)))
struct ToolRunTests {
    private static let shell = URL(fileURLWithPath: "/bin/sh")

    private func shell(_ script: String, timeout: TimeInterval? = nil, readsErrors: Bool = false) -> ToolRun {
        ToolRun(Self.shell, ["-c", script], timeout: timeout, readsErrors: readsErrors)
    }

    @Test("what it printed and its exit status, waited for or blocking; its errors only when asked")
    func outputAndStatus() async {
        let done = await shell("echo hello; echo oops >&2; exit 3").run()
        #expect(done == ToolRun.Result(status: 3, output: Data("hello\n".utf8)))
        #expect(!done.succeeded && done.text == "hello\n")
        let blocking = shell("echo hello; echo oops >&2", readsErrors: true).runBlocking()
        #expect(blocking.succeeded && blocking.text == "hello\noops\n")
    }

    @Test("more than a pipe holds is read as it comes, so the tool never stalls; what's kept has a limit")
    func largeOutput() async {
        #expect(await shell("head -c 300000 /dev/zero").run().output.count == 300_000)
        #expect(shell("head -c 300000 /dev/zero").runBlocking().output.count == 300_000)
        let endless = await shell("yes", timeout: 0.5).run()
        #expect(endless.timedOut && endless.output.isEmpty)
        #expect(ToolRun.maxOutput == 16 << 20)
    }

    @Test("one that can't start, or that a signal ends, says so")
    func notStartedOrSignaled() async {
        let missing = await ToolRun(URL(fileURLWithPath: "/nonexistent/tool")).run()
        #expect(missing == .notStarted && missing.status == -1 && !missing.timedOut)
        #expect(ToolRun(URL(fileURLWithPath: "/nonexistent/tool")).runBlocking() == .notStarted)
        let killed = await shell("kill -9 $$").run()
        #expect(killed.bySignal && killed.status == 9 && !killed.succeeded)
    }

    @Test("at its timeout it's stopped, and the run ends then, even when the tool ignores the stop")
    func timeout() async {
        let started = Date()
        let stubborn = await shell("trap '' TERM; sleep 5", timeout: 0.3).run()
        #expect(stubborn.timedOut && stubborn.status == -1)
        #expect(Date().timeIntervalSince(started) < 4)
        let blocking = shell("sleep 5", timeout: 0.3).runBlocking()
        #expect(blocking.timedOut)
        #expect(Date().timeIntervalSince(started) < 8)
        #expect(await shell("echo quick", timeout: 10).run().succeeded) // in time: as without one
    }

    /// Its lines and end, as `start` gives them.
    private final class Lines: Sendable {
        let lines = OSAllocatedUnfairLock<[String]>(initialState: [])
        let ended = OSAllocatedUnfairLock<(lines: Int, result: ToolRun.Result)?>(initialState: nil)

        func start(_ run: ToolRun) throws -> ToolRun.Running {
            try run.start(onLine: { line in self.lines.withLock { $0.append(line) } },
                          onEnd: { result in
                              let count = self.lines.withLock { $0.count }
                              self.ended.withLock { $0 = (count, result) }
                          })
        }

        func waitForEnd() async -> (lines: Int, result: ToolRun.Result)? {
            await TestWait.until { ended.withLock { $0 } != nil }
            return ended.withLock { $0 }
        }
    }

    @Test("started, each line comes as it's printed (the last without its line break too), then its end, after the last line")
    func lines() async throws {
        let seen = Lines()
        _ = try seen.start(shell("printf 'one\\ntwo\\n'; echo three >&2; printf four", readsErrors: true))
        let end = try #require(await seen.waitForEnd())
        #expect(seen.lines.withLock { $0 } == ["one", "two", "three", "four"])
        #expect(end.lines == 4 && end.result.succeeded && end.result.output.isEmpty)
        #expect(throws: (any Error).self) { try ToolRun(URL(fileURLWithPath: "/nonexistent/tool")).start(onLine: { _ in }, onEnd: { _ in }) }
    }

    @Test("Stop asks it to stop: it ends by the signal, unless it handles it")
    func stop() async throws {
        let plain = Lines()
        let running = try plain.start(shell("echo started; exec sleep 10"))
        await TestWait.until { !plain.lines.withLock { $0.isEmpty } }
        #expect(running.isRunning)
        running.stop()
        let stopped = try #require(await plain.waitForEnd())
        #expect(stopped.result.bySignal && stopped.result.status == SIGTERM && !running.isRunning)

        // One that puts things back first, then exits as it says.
        let tidy = Lines()
        let handling = try tidy.start(shell("trap 'echo tidied; exit 5' TERM; echo started; sleep 10 >/dev/null & wait"))
        await TestWait.until { !tidy.lines.withLock { $0.isEmpty } }
        handling.stop()
        let ended = try #require(await tidy.waitForEnd())
        #expect(ended.result == ToolRun.Result(status: 5))
        #expect(tidy.lines.withLock { $0 } == ["started", "tidied"])
    }
}
