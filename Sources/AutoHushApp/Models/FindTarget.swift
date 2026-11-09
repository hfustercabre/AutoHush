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
    init?(window: Window, settingsPage: SettingsPage?, hasApps: Bool,
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
