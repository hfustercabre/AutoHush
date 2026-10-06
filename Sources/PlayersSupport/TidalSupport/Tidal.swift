import Foundation
import AutoHushKit
import MenuPlayers

extension MenuPlayerProfile {
    /// TIDAL for macOS. It can't be scripted, so AutoHush presses Play/Pause
    /// in its Playback menu. TIDAL rebuilds that menu whenever its state
    /// changes, and disables Play/Pause while nobody is logged in.
    package static let tidal = MenuPlayerProfile(
        bundleID: "com.tidal.desktop",
        name: "TIDAL",
        menuName: "Playback",
        readWords: TidalWords.read(fromAppAt:),
        iconPlaceholder: .tidal
    )
}
