import AppKit
import AutoHushKit

// AppDelegate: what the menu's items do.
extension AppDelegate {
    func openSettings(page: SettingsWindowController.Page? = nil) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(model: settingsModel)
        }
        settingsWindowController?.show(page: page)
        refreshPlayerOptions()
        windowWatch.wake()
    }

    /// What each window shows that the window watch follows while it's open
    /// (Settings counts as open minimized too). macOS doesn't announce a
    /// change to these: notifications turned on or off, or reset, in System
    /// Settings (a reset is asked about again), a permission allowed (a
    /// window waiting for one goes on by itself), and the players installed
    /// while none is chosen (once one is, the folder watch follows them:
    /// `refreshPlayerOptions`) or while Add a Web App waits for the one it
    /// made to be listed.
    func registerWatchedWindows() {
        windowWatch.register(isOpen: { [weak self] in self?.settingsWindowController?.window?.isOpen == true }) { [weak self] in
            Self.settingsNeeds(page: self?.settingsWindowController?.shownPage, hasPlayer: self?.player != nil)
        }
        windowWatch.register(isOpen: { [weak self] in self?.isShowingPlayerChooser == true }) { [weak self] in
            self?.player == nil ? [.players, .notifications, .permissions] : [.notifications, .permissions]
        }
        windowWatch.register(isOpen: { [weak self] in self?.learningWindow?.isOpen == true }) { [.permissions] }
        // While it says a web app it made can't be found, the players too.
        windowWatch.register(isOpen: { [weak self] in self?.addWebAppWindow?.isOpen == true }) { [weak self] in
            self?.webAppAwaitingListing == nil ? [.permissions] : [.permissions, .players]
        }
    }

    /// What Settings needs followed while it's open, on `page`: the
    /// notifications, launch at login and the permissions, Diagnostics while
    /// its page shows, and the players while none is chosen.
    static func settingsNeeds(page: SettingsWindowController.Page?, hasPlayer: Bool) -> Set<WindowWatch.Refresh> {
        var needs: Set<WindowWatch.Refresh> = [.notifications, .launchAtLogin, .permissions]
        if page == .diagnostics { needs.insert(.diagnostics) }
        if !hasPlayer { needs.insert(.players) }
        return needs
    }

    /// One of the window watch's refreshes.
    func refresh(_ need: WindowWatch.Refresh) async {
        switch need {
        case .players:
            refreshPlayerOptions()
        case .diagnostics:
            refreshDiagnostics()
        case .notifications:
            let off = await updates.followNotificationPermission() == .off
            if settingsModel.notificationsOff != off { settingsModel.notificationsOff = off }
        case .launchAtLogin:
            settingsModel.refreshLaunchAtLogin()
        case .permissions:
            await refreshPermissions()
        }
    }

    /// The welcome window closed while it asked for the permissions: done,
    /// as with its Done button.
    func followWelcomeClosed() {
        if settingsModel.welcomeAsksPermissions, !isShowingPlayerChooser { finishWelcome() }
    }

    /// Edit → Find… (⌘F): opens Settings → Sound Sources' search while it lists
    /// apps, or puts the keyboard in a search already open there, in the
    /// welcome window's over its players, in the logs window's or in Add an
    /// App's list of apps. The item is dimmed elsewhere.
    func find() {
        guard let target = findTarget else { return }
        if target == .soundSourcesSearch, settingsModel.appSearch == nil {
            settingsModel.appSearch = "" // it opens, taking the keyboard as it appears
        } else if let window = NSApp.keyWindow, let field = window.contentView?.firstEditableTextField {
            window.makeFirstResponder(field)
        }
    }

    /// Where Find… goes in the window in front; `nil` where there's no search.
    var findTarget: FindTarget? {
        guard let window = NSApp.keyWindow else { return nil }
        let front: FindTarget.Window = window === settingsWindowController?.window ? .settings
            : window === logsWindowController?.window ? .logs
            : window.windowController is AppChooserWindowController ? .appChooser
            : window.windowController is PlayerChooserWindowController ? .welcome : .other
        return FindTarget(window: front, settingsPage: settingsWindowController?.shownPage, hasApps: !settingsModel.apps.isEmpty,
                          welcomeShowsPlayers: !settingsModel.welcomeAsksPermissions,
                          playersSearchable: settingsModel.playerOptions.isSearchable)
    }
}

/// The search Edit → Find… (⌘F) goes to in the window in front.
enum FindTarget: Equatable {
    /// Settings → Sound Sources' search, which Find opens.
    case soundSourcesSearch
    /// The welcome window's search over its players.
    case welcomeSearch
    /// The logs window's search.
    case logsSearch
    /// Add an App's list of apps to choose: its search.
    case appChooserSearch

    enum Window { case settings, welcome, logs, appChooser, other }

    /// Settings on Sound Sources while it lists apps (its magnifier is dimmed
    /// otherwise), the welcome window on its players while they're many
    /// enough for a search, the logs window, or Add an App's list of apps;
    /// `nil` anywhere else.
    init?(window: Window, settingsPage: SettingsWindowController.Page?, hasApps: Bool,
          welcomeShowsPlayers: Bool, playersSearchable: Bool) {
        switch window {
        case .settings where settingsPage == .soundSources && hasApps: self = .soundSourcesSearch
        case .welcome where welcomeShowsPlayers && playersSearchable: self = .welcomeSearch
        case .logs: self = .logsSearch
        case .appChooser: self = .appChooserSearch
        default: return nil
        }
    }
}
