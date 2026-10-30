@testable import CheckedPlayers
import Foundation
import AutoHushKit
import AutoHushTestSupport
import PlayersTestSupport

/// The apps added with Add an App, as the catalog finds them: a stand-in for
/// each setup kept (one that lets go of what it turned on in its app as it
/// goes back off), made again when its setup changes (checked again), as
/// `CheckedPlayers` makes them.
final class AddedApps: Sendable {
    private let setups: MemorySetupStore
    private let needReopening: Bool
    private let made = Locked<[String: (setup: PlayerSetup, player: MockMusicPlayer)]>([:])

    init(_ setups: MemorySetupStore, needReopening: Bool = false) {
        self.setups = setups
        self.needReopening = needReopening
    }

    func players() -> [any MusicPlayer] {
        let kept = setups.setups()
        return made.withLock { made in
            kept.map { setup in
                if let known = made[setup.bundleID], known.setup == setup { return known.player }
                let player = MockMusicPlayer(bundleID: setup.bundleID, name: setup.name, canFade: false, kind: .checkedApp,
                                             releasesOnQuit: true, needsReopening: needReopening)
                made[setup.bundleID] = (setup, player)
                return player
            }
        }
    }

    /// The one made last for `bundleID`.
    func player(_ bundleID: String) -> MockMusicPlayer? { made.value[bundleID]?.player }
}
