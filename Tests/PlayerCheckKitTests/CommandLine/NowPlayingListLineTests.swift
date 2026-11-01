import Foundation
import Testing
@testable import PlayerCheckKit

/// The Now Playing list as the helper writes it is read back the same.
@Suite("NowPlayingListLine")
struct NowPlayingListLineTests {
    @Test("the Now Playing list: each app's line, then the active one's process")
    func nowPlayingList() {
        let app = NowPlayingListLine(bundleID: "com.example.player", pid: 412, state: NowPlayingListLine.playing, isActive: true, name: "Player")
        #expect(app.line == "com.example.player\t412\tPlaying\t1\tPlayer")
        #expect(NowPlayingListLine(line: app.line) == app)
        let removed = NowPlayingListLine(bundleID: "com.example.gone", pid: 12, state: NowPlayingListLine.removed, isActive: false, name: "")
        #expect(NowPlayingListLine(line: removed.line) == removed)
        #expect(NowPlayingListLine.activeLine(412) == "#active\t412")
        #expect(NowPlayingListLine.active(in: NowPlayingListLine.activeLine(-1)) == -1)
        #expect(NowPlayingListLine(line: NowPlayingListLine.activeLine(412)) == nil)
        #expect(NowPlayingListLine.active(in: app.line) == nil)
        #expect(NowPlayingListLine(line: "can't read macOS's log") == nil)
    }
}
