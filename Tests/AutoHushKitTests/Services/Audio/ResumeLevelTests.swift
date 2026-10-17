import Foundation
import Testing
@testable import AutoHushKit

@Suite("ResumeLevel")
struct ResumeLevelTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    /// The music heard at `rms` for 3 s, fading out to a tenth, then paused by AutoHush.
    private func paused(_ rms: Float = 0.1) -> ResumeLevel {
        var level = ResumeLevel()
        for tick in 0..<12 { level.noteMusic(rms: rms, at: start.addingTimeInterval(Double(tick) * 0.25)) }
        level.noteMusic(rms: rms / 3, at: start.addingTimeInterval(3.1))
        level.noteMusic(rms: rms / 10, at: start.addingTimeInterval(3.3))
        level.setMusicPaused(true, at: start.addingTimeInterval(3.4))
        return level
    }

    @Test("the music's loudness is its loudest second before the pause, the fade-out aside; the apps' is their average during the pause; the volume goes down to theirs, 10 dB at most, and only when they were 2 dB quieter or more")
    func offset() throws {
        var level = paused()
        #expect(abs(try #require(level.reference) - 0.1) < 0.0001)
        #expect(level.offsetDB(maxCut: 10, minCut: 2) == nil) // no app heard yet

        level.noteApps(rms: 0.05)
        level.noteApps(rms: 0.05)
        #expect(abs(try #require(level.offsetDB(maxCut: 10, minCut: 2)) + 6.02) < 0.01)

        var quieter = paused()
        quieter.noteApps(rms: 0.01) // 20 dB quieter
        #expect(quieter.offsetDB(maxCut: 10, minCut: 2) == -10)

        var close = paused()
        close.noteApps(rms: 0.09) // 1 dB quieter
        #expect(close.offsetDB(maxCut: 10, minCut: 2) == nil)
        var louder = paused()
        louder.noteApps(rms: 0.3)
        #expect(louder.offsetDB(maxCut: 10, minCut: 2) == nil) // never up
    }

    @Test("apps heard while the music isn't paused don't count, and a resume forgets everything")
    func forgets() {
        var level = ResumeLevel()
        level.noteApps(rms: 0.01)
        level.noteMusic(rms: 0.1, at: start)
        level.setMusicPaused(true, at: start.addingTimeInterval(0.5))
        #expect(level.appsLevel == nil)
        level.noteApps(rms: 0.01)
        level.setMusicPaused(false, at: start.addingTimeInterval(9))
        #expect(level.reference == nil && level.appsLevel == nil)
        #expect(level.offsetDB(maxCut: 10, minCut: 2) == nil)
    }
}
