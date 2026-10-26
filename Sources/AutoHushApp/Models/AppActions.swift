import Foundation
import AutoHushKit

/// What only AppDelegate does, asked of it by Settings, the other windows
/// and the menu: choosing a player and the windows that go with it, the
/// permissions, Diagnostics, reopening and quitting. The rest goes straight
/// to the module that owns it: `UserSettings`, `UpdateCommands`, the learning
/// session and the player session.
@MainActor
protocol AppActions: AnyObject {
    /// Makes `bundleID` the player AutoHush controls; a suggested web app
    /// opens "Add a Web App" instead.
    func choosePlayer(_ bundleID: String)
    /// Opens the "Add a Web App" window.
    func openAddWebApp()
    /// Opens the "Add an App" window, which checks an app and adds it.
    func openAddApp()
    /// Removes an app added with Add an App, once the user confirms (its
    /// tile's ×, or Option in the menu).
    func removeAddedApp(_ bundleID: String)
    /// Learns the chosen player's controls afresh, in a new learning window.
    func learnControlsAgain()
    /// A missing permission's button: macOS's prompt, System Settings,
    /// opening the player, or reopening AutoHush (`PermissionCenter`).
    func requestPermission(_ permission: Permission)
    /// The welcome window is done: the player chosen, what it needs allowed.
    func finishWelcome()
    /// Brings Settings → Diagnostics up to date.
    func refreshDiagnostics()
    /// The menu is about to open: a last chance to bring what it shows up
    /// to date (e.g. which players are installed) before it's built.
    func menuWillOpen()
    /// Quits the chosen player and opens it again with what it needs
    /// (`AppStatus.playerNeedsReopen`).
    func reopenPlayer()
    /// Lifts the mute of a player that's muted instead of paused, until the
    /// other apps stop: as if the user played it (AutoHush leaves it alone).
    func unmutePlayer()
    /// Quits and opens AutoHush again, so macOS applies System Audio
    /// Recording (see `AppStatus.offersReopen`).
    func reopenAutoHush()
    /// Settings, on `page` (the one shown last when `nil`).
    func openSettings(page: SettingsWindowController.Page?)
    /// Why the media player couldn't be controlled, in an alert.
    func showControlError()
    /// The window with AutoHush's logs (Settings → Diagnostics' Show Logs…).
    func showLogs()
    /// System Settings, on AutoHush's notifications.
    func openNotificationSettings()
    /// Makes the menu bar icon again, so it goes beside the system's icons
    /// (Settings → General's switch, turned on).
    func moveMenuBarIconNearSystemIcons()
    /// Whether the menu bar icon is hidden now: behind the notch, or off the
    /// screen (`MenuBarIconVisibility`).
    var menuBarIconIsHidden: Bool { get }
    /// Try Again on "Couldn't resume" (Settings → General's player card).
    func retryResume()
    func quit()
}
