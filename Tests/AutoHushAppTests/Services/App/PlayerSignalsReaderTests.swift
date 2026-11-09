import AppKit
import Testing
@testable import AutoHushApp

/// The live reader, on what reading it can't change (the 2026-11-06 full
/// check's T-16): Finder, never a player. Its sound and Now Playing read is
/// left out: Now Playing's answer comes from a fresh copy of the running
/// executable, here the test runner.
@Suite("PlayerSignalsReader")
struct PlayerSignalsReaderTests {
    @Test("the live reader finds the apps open among those asked, with their process IDs", .enabled(
        if: !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").isEmpty, "no Finder running here"))
    @MainActor
    func liveOpen() throws {
        let finder = try #require(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first)
        let open = PlayerSignalsReader.live.open(["com.apple.finder", "com.example.not-installed"])
        #expect(open == ["com.apple.finder": finder.processIdentifier])
    }

    @Test("with no app open, the live reader finds none playing, without reading anything")
    func liveNoneOpen() async {
        #expect(await PlayerSignalsReader.live.playing([:]).isEmpty)
    }
}
