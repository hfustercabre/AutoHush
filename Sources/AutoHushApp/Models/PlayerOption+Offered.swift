import Foundation
import AutoHushKit

extension PlayerOption {
    /// From this many players on, the menu and the welcome window offer a
    /// search over them (Settings shows every tile on a page that scrolls).
    static let searchThreshold = 8
}

extension [PlayerOption] {
    /// How players are offered: the supported apps, then the apps added
    /// through a check (`PlayerOption.otherAppsHeading` goes over them),
    /// installed ones first in both; then the Safari web apps
    /// (`PlayerOption.webAppsHeading`): those of tested sites, the tested
    /// sites not added yet, then the untested ones; each group in the
    /// catalog's order.
    var offered: [PlayerOption] {
        let apps = filter { $0.kind == .app }
        let checkedApps = filter { $0.kind == .checkedApp }
        let webApps = filter { $0.kind == .safariWebApp }
        return apps.filter(\.isInstalled) + apps.filter { !$0.isInstalled }
            + checkedApps.filter(\.isInstalled) + checkedApps.filter { !$0.isInstalled }
            + webApps.filter { $0.webAddress == nil && !$0.isUntested } + webApps.filter { $0.webAddress != nil }
            + webApps.filter(\.isUntested)
    }

    /// These players as offered with AntiDot mode `on` or off: while it's
    /// on, the apps only their sound tells about can't be chosen
    /// (`PlayerOption.isUnavailableInAntiDotMode`).
    func inAntiDotMode(_ on: Bool) -> [PlayerOption] {
        map { option in
            var option = option
            option.isUnavailableInAntiDotMode = on && option.needsAudioLevels
            return option
        }
    }

    /// Long enough to need a search: `PlayerOption.searchThreshold` or more,
    /// not counting the suggested web apps.
    var isSearchable: Bool { count(where: { $0.webAddress == nil }) >= PlayerOption.searchThreshold }

    /// The players whose names contain `search`, ignoring case and accents;
    /// all of them while it's empty.
    func matching(_ search: String) -> [PlayerOption] {
        let search = search.trimmingCharacters(in: .whitespaces)
        guard !search.isEmpty else { return self }
        return filter { $0.name.localizedStandardContains(search) }
    }
}
