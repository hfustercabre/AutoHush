import Foundation
import Testing
@testable import WebAppPlayers

@Suite("PlayingPages")
struct PlayingPagesTests {
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
