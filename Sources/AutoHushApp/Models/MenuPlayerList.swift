import Foundation
import AutoHushKit

/// The players the menu offers, in the side window beside Media Player's row: the
/// supported apps, the apps added with Add an App (then Add an App…), and
/// the Safari web apps (then Add a Web App…), each with what its row says.
/// From `PlayerOption.searchThreshold` players on, a search comes first and
/// narrows them down.
struct MenuPlayerList: Equatable {
    /// One player's row.
    struct Row: Equatable, Identifiable {
        let option: PlayerOption
        /// The chosen player: checked.
        let isChosen: Bool
        /// Whether it can be chosen: installed (or a suggested web app), and
        /// not an app that can only be muted while AntiDot mode is on.
        let isEnabled: Bool
        /// Under its name: why it can't be chosen, or how it's controlled.
        let subtitle: String?
        /// Its tooltip and VoiceOver help: why AntiDot mode rules it out.
        let help: String?
        /// What VoiceOver says for it (`PlayerOption.spokenName`, its badge).
        let accessibilityLabel: String
        /// Added with Add an App: with Option held, its row removes it.
        var isRemovable: Bool { option.kind == .checkedApp }

        var id: String { option.bundleID }
    }

    /// Whether the search shows: from `PlayerOption.searchThreshold` players on.
    let showsSearch: Bool
    /// Instead of the players when the search matched none.
    let noMatchNote: String?
    let supportedApps: [Row]
    /// Whether "Other Apps" shows: always, unless a search matched none of them.
    let showsOtherApps: Bool
    let otherApps: [Row]
    let webApps: [Row]

    /// `options` as the menu offers them (in AntiDot mode, an app that can
    /// only be muted can't be chosen), narrowed by `search`.
    init(options: [PlayerOption], chosenID: String?, antiDotMode: Bool, search: String) {
        let offered = options.inAntiDotMode(antiDotMode).offered
        let shown = search.isEmpty ? offered : offered.matching(search)
        func row(_ option: PlayerOption) -> Row {
            var subtitle: String?
            var help: String?
            if !option.isInstalled {
                subtitle = option.webAddress != nil ? PlayerOption.clickToAddLabel : PlayerOption.notInstalledLabel
            } else if option.isUnavailableInAntiDotMode {
                subtitle = PlayerOption.antiDotModeLabel
                help = option.antiDotModeReason
            } else if option.pausesByMuting {
                subtitle = PlayerOption.mutedInsteadLabel
            }
            // VoiceOver can't see an icon's badge: a Safari web app named as an
            // app is says so, as a Chromium browser's web app says whose it is.
            let spoken = option.spokenName(among: options)
            return Row(option: option, isChosen: option.bundleID == chosenID, isEnabled: option.isClickable,
                       subtitle: subtitle, help: help,
                       accessibilityLabel: option.isUntested ? "\(spoken), \(PlayerOption.untestedBadge)" : spoken)
        }
        showsSearch = offered.isSearchable
        noMatchNote = shown.isEmpty ? PlayerOption.noMatchNote(search) : nil
        supportedApps = shown.filter { $0.kind == .app }.map(row)
        otherApps = shown.filter { $0.kind == .checkedApp }.map(row)
        // While a search narrows the players, the heading shows only over a match.
        showsOtherApps = !otherApps.isEmpty || search.isEmpty
        webApps = shown.filter { $0.kind == .safariWebApp }.map(row)
    }

    /// The players that can be chosen, top to bottom: Return with nothing
    /// highlighted chooses the first.
    var choosable: [Row] {
        (supportedApps + otherApps + webApps).filter(\.isEnabled)
    }
}
