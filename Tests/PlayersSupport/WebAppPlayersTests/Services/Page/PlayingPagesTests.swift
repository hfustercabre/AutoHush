import Foundation
import IOKit.pwr_mgt
import Testing
@testable import WebAppPlayers

@Suite("PlayingPages")
struct PlayingPagesTests {
    @Test("a browser's playing pages, and whether its web app is one of them; read from macOS's power assertions")
    func pages() throws {
        let assertions: [[String: Any]] = [
            ["AssertName": "Playing audio"], ["AssertName": "Playing audio"],
            ["AssertName": "Playing audio", "AssertionOnBehalfOfPID": 42], ["AssertName": "Video Wake Lock"],
        ]
        #expect(PlayingPages.count(in: assertions) == 2)
        #expect(PlayingPages.webAppPlays(total: 2, others: 1) == true)
        #expect(PlayingPages.webAppPlays(total: 1, others: 1) == false)
        #expect(PlayingPages.webAppPlays(total: 3, others: 1) == nil)

        // This process holding one, as a Chromium browser does for a page that plays.
        #expect(PlayingPages.count(ofBrowser: getpid()) == 0)
        var id = IOPMAssertionID(0)
        try #require(IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn), "Playing audio" as CFString,
                                                 &id) == kIOReturnSuccess)
        #expect(PlayingPages.count(ofBrowser: getpid()) == 1)
        IOPMAssertionRelease(id)
        #expect(PlayingPages.count(ofBrowser: getpid()) == 0)
    }
}
