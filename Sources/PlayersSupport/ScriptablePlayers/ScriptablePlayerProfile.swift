import Foundation
import AutoHushKit

/// What AutoHush needs to know about a music app it controls with Apple
/// events: its codes (from the scripting dictionary in its bundle), the
/// notification it posts when its state changes, and its quirks. Each
/// `<App>Support` module describes its app with one.
package struct ScriptablePlayerProfile: Sendable {
    package let bundleID: String
    /// Shown to the user, e.g. "Spotify".
    let name: String
    /// The four-char code of the app's own suite, which holds pause and play.
    let suite: OSType
    /// Posted as a distributed notification on every play, pause, stop and
    /// track change, with the new state in userInfo["Player State"].
    package let stateNotification: Notification.Name
    /// How the app's volume number maps to loudness; measure it with
    /// `swift run measure-volume-curve <bundle-id>`.
    let volumeCurve: VolumeCurve
    /// The volume the app was set to, from the one it reports: an app that
    /// reports a different number would otherwise lose a step on every fade
    /// that restores the volume it read.
    let readVolume: @Sendable (Int) -> Int
    /// Drawn in place of the app's icon while it isn't installed.
    let iconPlaceholder: PlayerIconPlaceholder?

    package init(
        bundleID: String,
        name: String,
        suite: OSType,
        stateNotification: Notification.Name,
        volumeCurve: VolumeCurve = .linear,
        readVolume: @escaping @Sendable (Int) -> Int = { $0 },
        iconPlaceholder: PlayerIconPlaceholder? = nil
    ) {
        self.bundleID = bundleID
        self.name = name
        self.suite = suite
        self.stateNotification = stateNotification
        self.volumeCurve = volumeCurve
        self.readVolume = readVolume
        self.iconPlaceholder = iconPlaceholder
    }
}
