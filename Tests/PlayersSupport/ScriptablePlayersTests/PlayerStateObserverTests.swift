import AppKit
import Foundation
import Testing
@testable import ScriptablePlayers
import AutoHushKit
import AutoHushTestSupport

@Suite("PlayerStateObserver", .waitsTimeLimit)
struct PlayerStateObserverTests {
    private static let bundleID = "com.example.jukebox"


    @Test("maps the Player State values", arguments: [
        ("Playing", PlayerState.playing),
        ("Paused", .paused),
        ("Stopped", .stopped),
        ("playing", .playing),
        ("Buffering", .unknown),
    ])
    func mapsPlayerState(value: String, expected: PlayerState) {
        #expect(PlayerStateObserver.playerState(from: ["Player State": value]) == expected)
    }

    @Test("missing Player State maps to unknown")
    func missingPlayerStateIsUnknown() {
        #expect(PlayerStateObserver.playerState(from: nil) == .unknown)
        #expect(PlayerStateObserver.playerState(from: ["Track ID": "x"]) == .unknown)
    }

    @MainActor
    @Test("the player quitting is reported as notRunning; other apps are ignored")
    func terminationReportsNotRunning() async {
        let workspaceCenter = NotificationCenter()
        var received: [PlayerState] = []
        let observer = PlayerStateObserver(
            notification: Notification.Name("com.example.jukebox.state"), bundleID: Self.bundleID,
            workspaceCenter: workspaceCenter
        ) { received.append($0) }
        observer.start()

        postTermination(of: "com.apple.Safari", on: workspaceCenter)
        postTermination(of: Self.bundleID, on: workspaceCenter)
        // The workspace observer delivers on the main queue.
        await TestWait.until { !received.isEmpty }

        #expect(received == [.notRunning])
        observer.stop()
    }

    @MainActor
    @Test("nothing is delivered after stop")
    func nothingAfterStop() async {
        let workspaceCenter = NotificationCenter()
        var received: [PlayerState] = []
        let observer = PlayerStateObserver(
            notification: Notification.Name("com.example.jukebox.state"), bundleID: Self.bundleID,
            workspaceCenter: workspaceCenter
        ) { received.append($0) }
        observer.start()
        observer.stop()

        postTermination(of: Self.bundleID, on: workspaceCenter)
        // A delivery, on the main queue, would have come before this.
        await withCheckedContinuation { done in OperationQueue.main.addOperation { done.resume() } }

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
