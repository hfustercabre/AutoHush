import Foundation
import Testing
@testable import AutoHushKit

@Suite("NowPlayingApp")
struct NowPlayingAppTests {
    @Test("the fresh copy's answer is read back: a process, none, or unknown for anything else")
    func answers() {
        #expect(NowPlayingApp.answer(from: "process 2437\n") == .process(2437))
        #expect(NowPlayingApp.answer(from: "none\n") == .none)
        #expect(NowPlayingApp.answer(from: "unknown\n") == .unknown)
        #expect(NowPlayingApp.answer(from: "") == .unknown) // it crashed, or printed nothing
        #expect(NowPlayingApp.answer(from: "process 0") == .unknown)
        #expect(NowPlayingApp.answer(from: "process -1") == .unknown)
        #expect(NowPlayingApp.answer(from: "process") == .unknown)
        #expect(NowPlayingApp.answer(from: "process 12 34") == .unknown)
    }

    @Test("a copy that can't be started, or doesn't answer in time, gives unknown: the key is pressed as ever")
    func noAnswer() {
        #expect(NowPlayingApp.current(executable: nil) == .unknown)
        #expect(NowPlayingApp.current(executable: URL(fileURLWithPath: "/nonexistent/AutoHush")) == .unknown)
        // `yes` never ends by itself: stopped once its time is up.
        let started = Date()
        #expect(NowPlayingApp.current(executable: URL(fileURLWithPath: "/usr/bin/yes"), timeout: 0.3) == .unknown)
        #expect(Date().timeIntervalSince(started) < 2)
    }
}
