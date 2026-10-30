import Foundation
@testable import AutoHushKit

/// One that opts into neither, but says how late it reports.
struct ScriptedLikePlayer: MusicPlayer {
    let bundleID = "com.example.scripted"
    let name = "Scripted"
    let stateReportDelay: TimeInterval = 0
    func verifyControlAccess() async throws {}
    func playerState() async -> PlayerState { .paused }
    func pause() async throws {}
    func play() async throws {}
    func volume() async -> Int? { 50 }
    func setVolume(_ volume: Int) async throws {}
    @MainActor
    func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        PolledStateObserver(read: { .paused }, onChange: onChange)
    }
}
