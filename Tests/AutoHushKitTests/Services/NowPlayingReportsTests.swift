import Foundation
import os
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("NowPlayingReports")
struct NowPlayingReportsTests {
    @Test("the daemon's lines: each client created, its state changes, removed")
    func lines() {
        var clients: [pid_t: NowPlayingReports.Client] = [:]
        NowPlayingReports.apply("Creating nowPlayingClient com.deezer.deezer-desktop (812) Deezer", to: &clients)
        NowPlayingReports.apply("[com.deezer.deezer-desktop (812) Deezer ❯] PlaybackState changed from Paused to Playing", to: &clients)
        #expect(clients[812]?.state == .playing)
        #expect(clients[812]?.appID == "com.deezer.deezer-desktop")
        NowPlayingReports.apply("[com.apple.WebKit.GPU/com.apple.Safari.WebApp.ABC (723) YT Music ❯] PlaybackState changed from Playing to Paused",
                                to: &clients)
        #expect(clients[723]?.appID == "com.apple.Safari.WebApp.ABC")
        #expect(clients[723]?.state == .paused)
        NowPlayingReports.apply("Removing nowPlayingClient com.deezer.deezer-desktop (812) Deezer", to: &clients)
        #expect(clients[812]?.removed == true)
        #expect(NowPlayingReports.state(reported: "Interrupted") == .paused)
        #expect(NowPlayingReports.state(reported: "Stopped") == .stopped)
    }

    @Test("a client keeps its name, its report as the log says it, and when it came")
    func reports() {
        var clients: [pid_t: NowPlayingReports.Client] = [:]
        let at = Date(timeIntervalSince1970: 1_000)
        NowPlayingReports.apply("[com.qobuz.QobuzDesktop (90) Qobuz ❯] PlaybackState changed from Playing to Interrupted", at: at, to: &clients)
        #expect(clients[90]?.reported == "Interrupted")
        #expect(clients[90]?.state == .paused)
        #expect(clients[90]?.name == "Qobuz")
        #expect(clients[90]?.pid == 90)
        #expect(clients[90]?.changed == at)
    }

    @Test("the app's newest report, from a client that isn't removed and whose process still runs")
    func latest() {
        var clients: [pid_t: NowPlayingReports.Client] = [:]
        NowPlayingReports.apply("[com.example.app (10) App ❯] PlaybackState changed from Paused to Playing",
                                at: Date(timeIntervalSince1970: 1), to: &clients)
        NowPlayingReports.apply("[com.example.app (11) App ❯] PlaybackState changed from Playing to Paused",
                                at: Date(timeIntervalSince1970: 2), to: &clients)
        let running: Set<pid_t> = [10, 11]
        #expect(NowPlayingReports.latest(of: "com.example.app", in: clients, stillRuns: running.contains)?.pid == 11)
        // A crashed app's last report doesn't outlive it.
        #expect(NowPlayingReports.latest(of: "com.example.app", in: clients, stillRuns: { $0 == 10 })?.pid == 10)
        NowPlayingReports.apply("Removing nowPlayingClient com.example.app (10) App", to: &clients)
        #expect(NowPlayingReports.latest(of: "com.example.app", in: clients, stillRuns: { $0 == 10 }) == nil)
        #expect(NowPlayingReports.latest(of: "com.other", in: clients, stillRuns: running.contains) == nil)
        #expect(NowPlayingReports.stillRuns(getpid()) && !NowPlayingReports.stillRuns(0))
    }

    @Test("reports given in place of the log are read at once, and only what still runs counts")
    func given() {
        var clients: [pid_t: NowPlayingReports.Client] = [:]
        NowPlayingReports.apply("[com.example.app (\(getpid())) App ❯] PlaybackState changed from Paused to Playing", to: &clients)
        let reports = NowPlayingReports(clients: clients)
        #expect(reports.isAvailable)
        #expect(reports.state(of: "com.example.app") == .playing)
        reports.stop()
        #expect(reports.state(of: "com.example.app") == nil)
    }

    /// A folder of its own for a stream's script: the files it waits for, or writes.
    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NowPlayingReportsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test("the log followed: its past under the live lines; a stream that ends says nothing, and the next question follows it again")
    func followed() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let pid = getpid()
        // A web app's media process: it played as the web app, then is created again under WebKit's ID.
        var clients: [pid_t: NowPlayingReports.Client] = [:]
        NowPlayingReports.apply("[com.apple.WebKit.GPU/com.example.webapp (\(pid)) Web App ❯] PlaybackState changed from Paused to Playing",
                                to: &clients)
        let past = clients
        let lines = ["Creating nowPlayingClient com.apple.WebKit.GPU (\(pid)) ",
                     "[com.apple.WebKit.GPU/com.example.webapp (\(pid)) Web App ❯] PlaybackState changed from Playing to Paused"]
            .map { #"{"eventMessage":"\#($0)"}"# }
        // Its first line (and one that isn't JSON), its second once "more" exists, its end once "end" does.
        let script = #"printf '%s\n' "$1" 'not JSON'; until [ -e "$3/more" ]; do sleep 0.01; done; printf '%s\n' "$2"; until [ -e "$3/end" ]; do sleep 0.01; done"#
        let reads = OSAllocatedUnfairLock(initialState: [Date]())
        let reports = NowPlayingReports(idleLimit: nil, streamCommand: ["/bin/sh", "-c", script, "sh"] + lines + [folder.path]) { since in
            Thread.sleep(forTimeInterval: 0.1) // the live line comes first
            reads.withLock { $0.append(since) }
            return past
        }
        defer { reports.stop() }
        let webApp = "com.example.webapp"
        let since = Date(timeIntervalSinceNow: -30)
        #expect(reports.follow(since: since))
        #expect(reads.withLock { $0 } == [since])
        // The live line says only that it's there: its name, ID and report are the past's.
        #expect(reports.state(of: webApp) == .playing)
        #expect(reports.latest(of: webApp)?.name == "Web App")
        try Data().write(to: folder.appendingPathComponent("more"))
        await TestWait.until { reports.state(of: webApp) == .paused }
        #expect(reports.state(of: webApp) == .paused)
        try Data().write(to: folder.appendingPathComponent("end"))
        // Nothing said once it ended; that question follows it again, its past read back `lookBack`.
        await TestWait.until { reports.state(of: webApp) == nil }
        await TestWait.until { reads.withLock { $0.count } == 2 }
        let again = try #require(reads.withLock { $0.dropFirst().first })
        #expect(abs(again.timeIntervalSinceNow + NowPlayingReports.firstLookBack) < 5)
    }

    @Test("followed until nobody asks for its idle limit, or until stop; a log that can't be opened isn't asked again")
    func idle() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("pid").path
        let line = #"{"eventMessage":"[com.example.app (\#(getpid())) App ❯] PlaybackState changed from Paused to Playing"}"#
        // Its pid written, its line, then it waits.
        let reports = NowPlayingReports(idleLimit: 0.2, streamCommand: ["/bin/sh", "-c", #"echo $$ > "$1"; printf '%s\n' "$2"; exec sleep 60"#,
                                                                        "sh", file, line]) { _ in [:] }
        func stream() -> pid_t? {
            (try? String(contentsOfFile: file, encoding: .utf8)).flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        #expect(reports.follow(since: Date()))
        await TestWait.until { reports.state(of: "com.example.app") == .playing }
        #expect(reports.state(of: "com.example.app") == .playing)
        let first = try #require(stream())
        await TestWait.until { !NowPlayingReports.stillRuns(first) }
        #expect(!NowPlayingReports.stillRuns(first))
        #expect(reports.state(of: "com.example.app") == nil)
        await TestWait.until { reports.state(of: "com.example.app") == .playing }
        let second = try #require(stream())
        #expect(second != first)
        reports.stop()
        await TestWait.until { !NowPlayingReports.stillRuns(second) }
        #expect(!NowPlayingReports.stillRuns(second))

        let closed = NowPlayingReports(streamCommand: ["/bin/sh", "-c", "exec sleep 60"]) { _ in nil }
        #expect(!closed.follow(since: Date()))
        #expect(!closed.isAvailable)
        #expect(closed.state(of: "com.example.app") == nil)
    }
}
