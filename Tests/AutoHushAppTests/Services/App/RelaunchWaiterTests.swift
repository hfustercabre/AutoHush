import Foundation
import Testing
@testable import AutoHushApp
import AutoHushTestSupport

@Suite("RelaunchWaiter", .waitsTimeLimit)
struct RelaunchWaiterTests {
    @Test("after an update, AutoHush opens again once it has quit, once, and not at all when the relaunch is cancelled")
    func openAfterExit() async throws {
        let folder = TemporaryFolder("RelaunchWaiterTests")
        let opened = folder.appending(path: "opened.txt"), opener = folder.appending(path: "open.sh")
        try "#!/bin/sh\necho \"$1\" >> \"\(opened.path)\"\n".write(to: opener, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: opener.path)
        func openedApps() -> String? { try? String(contentsOf: opened, encoding: .utf8) }
        /// A process standing for AutoHush, until it's ended.
        func running() throws -> Process {
            let process = Process()
            process.executableURL = URL(filePath: "/bin/sleep")
            process.arguments = ["30"]
            try process.run()
            return process
        }
        /// Whether the loop with `pid` is gone: nothing more can open then.
        func gone(_ pid: pid_t) -> Bool { kill(pid, 0) != 0 }
        let app = URL(filePath: "/Applications/AutoHush.app")
        // The loop looks every 0.02 s here: 0.1 s is five looks.
        let look = 0.02, fiveLooks = Duration.milliseconds(100)
        let autoHush = try running()
        let first = try RelaunchWaiter.openAfterExit(app, waitingFor: autoHush.processIdentifier, opener: opener, lookingEvery: look)
        try await Task.sleep(for: fiveLooks)
        #expect(openedApps() == nil && !gone(first.waiter)) // still running
        autoHush.terminate()
        autoHush.waitUntilExit()
        await TestWait.until { gone(first.waiter) }
        #expect(openedApps() == app.path + "\n") // once

        let again = try running()
        let cancelled = try RelaunchWaiter.openAfterExit(app, waitingFor: again.processIdentifier, opener: opener, lookingEvery: look)
        cancelled.cancel()
        again.terminate()
        again.waitUntilExit()
        await TestWait.until { gone(cancelled.waiter) }
        #expect(openedApps() == app.path + "\n") // not again
        withExtendedLifetime(folder) {}
    }
}
