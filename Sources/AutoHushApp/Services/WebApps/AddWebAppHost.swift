import Foundation

/// What Add a Web App needs from the rest of AutoHush (`AddWebAppFeature`),
/// as Add an App's `AddAppHost`: AppDelegate is the host.
@MainActor
protocol AddWebAppHost: AnyObject {
    /// The chosen player's bundle ID; `nil` while none is chosen.
    var chosenPlayerID: String? { get }
    /// The chosen player has learned its controls already.
    var chosenPlayerIsLearned: Bool { get }
    /// The welcome window is open: it asks for what a web app needs.
    var isShowingPlayerChooser: Bool { get }
    /// Settings' model, which the window shows the learning by.
    var settingsForWindows: SettingsModel { get }
    /// Whether `bundleID` is a player AutoHush can control.
    func isPlayer(_ bundleID: String) -> Bool
    /// Makes the web app just added the player, showing the learning window
    /// or not (`AppDelegate.choosePlayer`).
    func chooseWebApp(_ bundleID: String, showsLearningWindow: Bool)
    /// Asks for what making a web app needs (Safari's Accessibility).
    func requestSafariAccess()
    /// Follows the open windows at once (the window watch).
    func followWindows()
}
