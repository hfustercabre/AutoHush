import Foundation
@testable import AutoHushKit

/// A player that opts into both: no volume, read now and then.
struct MenuLikePlayer: FadelessMusicPlayer, PolledMusicPlayer {
    let bundleID = "com.example.menu"
    let name = "Menu"
    func verifyControlAccess() async throws {}
    func playerState() async -> PlayerState { .paused }
    func pause() async throws {}
    func play() async throws {}
}
