import Foundation
import Testing
@testable import AutoHushApp

@Suite("OtherInstances")
struct OtherInstancesTests {
    /// Stand-in processes: which are running, which quit when asked, and the
    /// signals they got.
    private final class Processes: @unchecked Sendable {
        private let lock = NSLock()
        private var running: Set<pid_t>
        private let stubborn: Set<pid_t>
        private var _signals: [String] = []

        init(running: Set<pid_t>, stubborn: Set<pid_t> = []) {
            self.running = running
            self.stubborn = stubborn
        }

        var signals: [String] { lock.withLock { _signals } }

        var instances: OtherInstances {
            OtherInstances(
                list: { self.lock.withLock { self.running.sorted() } },
                send: { pid, signal in
                    self.lock.withLock {
                        self._signals.append("\(signal == SIGTERM ? "TERM" : "KILL") \(pid)")
                        if signal == SIGKILL || !self.stubborn.contains(pid) { self.running.remove(pid) }
                    }
                },
                isRunning: { pid in self.lock.withLock { self.running.contains(pid) } }
            )
        }
    }

    @Test("with no other copy running, nothing is sent")
    func alone() async {
        let processes = Processes(running: [])
        #expect(await processes.instances.quitAll() == [])
        #expect(processes.signals.isEmpty)
    }

    @Test("other copies are asked to quit, and nothing more once they have")
    func asksToQuit() async {
        let processes = Processes(running: [101, 102])
        #expect(await processes.instances.quitAll(grace: .seconds(1), poll: .milliseconds(10)) == [101, 102])
        #expect(processes.signals == ["TERM 101", "TERM 102"])
    }

    @Test("a copy that doesn't quit in time is forced to")
    func forcesStuckCopy() async {
        let processes = Processes(running: [101, 102], stubborn: [102])
        await processes.instances.quitAll(grace: .milliseconds(50), poll: .milliseconds(10))
        #expect(processes.signals == ["TERM 101", "TERM 102", "KILL 102"])
    }

    @Test("only copies opened before this one quit; opened together, the lower process ID does")
    func onlyOlderCopiesQuit() {
        let now = Date()
        #expect(OtherInstances.isOlder(launch: now - 60, pid: 500, than: now, ownPID: 400))
        #expect(!OtherInstances.isOlder(launch: now + 1, pid: 300, than: now, ownPID: 400))
        #expect(OtherInstances.isOlder(launch: now, pid: 300, than: now, ownPID: 400))
        #expect(!OtherInstances.isOlder(launch: now, pid: 500, than: now, ownPID: 400))
        #expect(!OtherInstances.isOlder(launch: now - 60, pid: 400, than: now, ownPID: 400)) // itself
        // A copy whose start is unknown quits, as before.
        #expect(OtherInstances.isOlder(launch: nil, pid: 500, than: now, ownPID: 400))
        #expect(OtherInstances.isOlder(launch: now, pid: 500, than: nil, ownPID: 400))
    }

    @Test("the live list leaves out this process")
    func liveListSkipsSelf() {
        // The test runner isn't an app, so only check this process is never listed.
        let instances = OtherInstances.live(bundleIdentifier: "com.autohush.AutoHush.not-running")
        #expect(instances.list().isEmpty)
    }

    @Test("a process ID taken by another process since isn't a copy still running, so it's never forced to quit")
    func reusedProcessID() {
        let instances = OtherInstances.live(bundleIdentifier: "com.autohush.AutoHush.not-running")
        #expect(!instances.isRunning(getpid())) // running, but not that app
        #expect(!instances.isRunning(99_999))   // no such process
    }
}
