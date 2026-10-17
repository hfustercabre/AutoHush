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

    @Test("what the copy prints is read back as the same answer: a copy asked with the argument answers in time")
    func lineRoundTrip() throws {
        for answer in [NowPlayingApp.Answer.process(2437), .none, .unknown] {
            #expect(NowPlayingApp.answer(from: NowPlayingApp.line(for: answer) + "\n") == answer)
        }
        // A stand-in copy that answers only when asked with the argument.
        let folder = FileManager.default.temporaryDirectory.appending(path: "NowPlayingAppTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appending(path: "AutoHush")
        try Data("#!/bin/sh\n[ \"$1\" = \"\(NowPlayingApp.argument)\" ] && echo 'process 4242'\n".utf8).write(to: copy)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: copy.path)
        #expect(NowPlayingApp.current(executable: copy, timeout: 10) == .process(4242))
    }

    @Test("a copy that can't be started, or doesn't answer in time, gives unknown: the key is pressed as ever")
    func noAnswer() {
        #expect(NowPlayingApp.current(executable: nil) == .unknown)
        #expect(NowPlayingApp.current(executable: URL(fileURLWithPath: "/nonexistent/AutoHush")) == .unknown)
        // `yes` never ends by itself: stopped once its time is up, not waited
        // for (however busy the Mac, well within 10 s).
        let started = Date()
        #expect(NowPlayingApp.current(executable: URL(fileURLWithPath: "/usr/bin/yes"), timeout: 0.3) == .unknown)
        #expect(Date().timeIntervalSince(started) < 10)
    }
}
