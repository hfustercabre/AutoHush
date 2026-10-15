import Foundation
import Testing
@testable import AutoHushKit

@Suite("NowPlayingReports and PlayingPages")
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

    @Test("a browser's playing pages, and whether its web app is one of them")
    func pages() {
        let assertions: [[String: Any]] = [
            ["AssertName": "Playing audio"], ["AssertName": "Playing audio"],
            ["AssertName": "Playing audio", "AssertionOnBehalfOfPID": 42], ["AssertName": "Video Wake Lock"],
        ]
        #expect(PlayingPages.count(in: assertions) == 2)
        #expect(PlayingPages.webAppPlays(total: 2, others: 1) == true)
        #expect(PlayingPages.webAppPlays(total: 1, others: 1) == false)
        #expect(PlayingPages.webAppPlays(total: 3, others: 1) == nil)
    }
}
