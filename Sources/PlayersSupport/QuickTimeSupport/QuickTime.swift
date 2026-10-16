import Foundation
import AutoHushKit
import ScriptablePlayers

/// QuickTime Player, the media player that comes with macOS, controlled by
/// its AppleScript, which acts on its documents (codes from
/// `QuickTime Player.app/Contents/Resources/QuickTimePlayerX.sdef`, 10.5):
/// `pause` goes to each document playing, `play` back to those it paused,
/// else to the front one, and each document's `playing` tells whether it
/// plays (`ScriptedAppPlayer`). It announces nothing, so its state is read
/// about once a second. It doesn't fade: its volume is each document's
/// `audio volume`, which AutoHush doesn't set.
package enum QuickTime {
    package static let bundleID = "com.apple.QuickTimePlayerX"
    package static let name = "QuickTime Player"

    package static let setup = ScriptSetup(
        commands: .pauseAndPlay(pause: "MVWRpaus", play: "MVWRplay"),
        actsOnDocuments: true,
        state: .documents(documentClass: "docu", playing: "play"),
        hasVolume: false
    )

    /// The player, as the catalog offers it.
    package static func player() -> ScriptedAppPlayer {
        ScriptedAppPlayer(bundleID: bundleID, name: name, setup: setup, iconPlaceholder: .quickTime)
    }
}
