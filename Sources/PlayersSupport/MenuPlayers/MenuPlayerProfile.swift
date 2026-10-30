import Foundation
import AutoHushKit

/// What AutoHush needs to know about a music app it controls through its
/// playback menu. Each `<App>Support` module describes its app with one.
package struct MenuPlayerProfile: Sendable {
    let bundleID: String
    /// Shown to the user, e.g. "TIDAL".
    let name: String
    /// The menu's English name, for error reports, e.g. "Playback".
    let menuName: String
    /// Reads the app's own words for Play and Pause from a copy of the app.
    let readWords: @Sendable (URL) -> PlayPauseWords?
    /// Drawn in place of the app's icon while it isn't installed.
    let iconPlaceholder: PlayerIconPlaceholder?

    package init(
        bundleID: String,
        name: String,
        menuName: String,
        readWords: @escaping @Sendable (URL) -> PlayPauseWords?,
        iconPlaceholder: PlayerIconPlaceholder? = nil
    ) {
        self.bundleID = bundleID
        self.name = name
        self.menuName = menuName
        self.readWords = readWords
        self.iconPlaceholder = iconPlaceholder
    }
}

extension MenuPlayerProfile {
    /// For an app added through a check, not described by a module of its
    /// own: its menu found as AutoHush finds any (`AccessibilityPlaybackMenu`),
    /// its state told by the words its bundle has for Play and Pause
    /// (`PlayPauseWords.found`), with the common ones.
    package static func found(bundleID: String, name: String, menuName: String) -> MenuPlayerProfile {
        MenuPlayerProfile(bundleID: bundleID, name: name, menuName: menuName,
                          readWords: { PlayPauseWords.common.merged(with: PlayPauseWords.found(inAppAt: $0)?.words) })
    }
}
