import Foundation
import Testing
@testable import AutoHushKit

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
}
