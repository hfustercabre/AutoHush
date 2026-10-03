import AppKit
import Foundation
import Testing
@testable import AutoHush

@Suite("SpotifyPlaybackObserver")
struct SpotifyPlaybackObserverTests {

    @Test("maps Spotify's Player State values", arguments: [
        ("Playing", PlayerState.playing),
        ("Paused", .paused),
        ("Stopped", .stopped),
        ("playing", .playing),
        ("Buffering", .unknown),
    ])
    func mapsPlayerState(value: String, expected: PlayerState) {
        #expect(SpotifyPlaybackObserver.playerState(from: ["Player State": value]) == expected)
    }

    @Test("missing Player State maps to unknown")
    func missingPlayerStateIsUnknown() {
        #expect(SpotifyPlaybackObserver.playerState(from: nil) == .unknown)
        #expect(SpotifyPlaybackObserver.playerState(from: ["Track ID": "x"]) == .unknown)
    }

    @MainActor
    @Test("Spotify terminating is reported as notRunning; other apps are ignored")
    func terminationReportsNotRunning() async {
        let workspaceCenter = NotificationCenter()
        var received: [PlayerState] = []
        let observer = SpotifyPlaybackObserver(workspaceCenter: workspaceCenter) { received.append($0) }
        observer.start()

        postTermination(of: "com.apple.Safari", on: workspaceCenter)
        postTermination(of: SpotifyPlayer.appBundleID, on: workspaceCenter)
        // The workspace observer delivers on the main queue.
        for _ in 0..<50 where received.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }

        #expect(received == [.notRunning])
        observer.stop()
    }

    @MainActor
    @Test("nothing is delivered after stop")
    func nothingAfterStop() async {
        let workspaceCenter = NotificationCenter()
        var received: [PlayerState] = []
        let observer = SpotifyPlaybackObserver(workspaceCenter: workspaceCenter) { received.append($0) }
        observer.start()
        observer.stop()

        postTermination(of: SpotifyPlayer.appBundleID, on: workspaceCenter)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(received.isEmpty)
    }

    /// NSRunningApplication can't be constructed for an arbitrary bundle ID,
    /// so the current process stands in with a swizzle-free subclass.
    private func postTermination(of bundleID: String, on center: NotificationCenter) {
        center.post(
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: FakeRunningApplication(bundleID: bundleID)]
        )
    }
}

private final class FakeRunningApplication: NSRunningApplication, @unchecked Sendable {
    private let fakeBundleID: String
    init(bundleID: String) {
        fakeBundleID = bundleID
        super.init()
    }
    override var bundleIdentifier: String? { fakeBundleID }
}
