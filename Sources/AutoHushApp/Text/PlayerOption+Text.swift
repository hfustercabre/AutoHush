import Foundation

/// The words wherever players are offered (the menu, Settings → Media
/// Player, the welcome window), and the chosen player's in Settings →
/// General and Diagnostics.
extension PlayerOption {
    /// "Media Player": the heading over the chosen player in Settings →
    /// General and Diagnostics, atop the players' side window beside the
    /// menu, and Settings' page with every player.
    static var mediaPlayerHeading: String {
        String(localized: "Media Player", comment: "Settings → General, Diagnostics and the menu's side window of players: heading over the media player; also a Settings page in the sidebar, with every player to choose from (keep it short, about 16 characters: the word for player is enough)")
    }

    /// Over the players that are apps, before the Safari web apps, wherever
    /// players are offered.
    static var supportedAppsHeading: String {
        String(localized: "Supported Apps",
               comment: "Where media players are offered (the menu, Settings → Media Player, the welcome window): heading over the players that are apps, before the “Safari Web Apps”")
    }

    /// Over the Safari web apps, after the apps, wherever players are offered.
    static var webAppsHeading: String {
        String(localized: "Safari Web Apps",
               comment: "Where media players are offered: heading over the websites added to the Dock from Safari")
    }

    /// Over the apps added through a check, after the supported apps,
    /// wherever players are offered.
    static var otherAppsHeading: String {
        String(localized: "Other Apps",
               comment: "Where media players are offered (the menu, Settings → Media Player, the welcome window): heading over the apps added through a check (Add an App…), after the “Supported Apps”")
    }

    /// After `otherAppsHeading`, as a `HeadingBadge`.
    static var checkedByYouBadge: String {
        String(localized: "Checked by you",
               comment: "Badge after the “Other Apps” heading where media players are offered: these apps were added through a check the user ran, not supported by AutoHush itself")
    }

    /// Under `otherAppsHeading` while no app has been added: what Add… does.
    static var otherAppsEmptyNote: String {
        String(localized: "Add any other app: a check finds how to pause and play it.",
               comment: "Where media players are offered, under the “Other Apps” heading while no app was added yet, over its Add… tile")
    }

    /// Under `otherAppsHeading` wherever players are offered.
    static var otherAppsNote: String {
        String(localized: "Controlled the ways a check found to work.",
               comment: "Where media players are offered, under the “Other Apps” heading and its “Checked by you” badge")
    }

    /// Where players are offered: the entry that checks an app and adds it.
    static var addAppTitle: String {
        String(localized: "Add an App…",
               comment: "Menu item and button where media players are offered: checks how AutoHush can pause and play an app it doesn't support yet, and adds it")
    }

    /// Where players are offered: the entry that adds a Safari web app.
    static var addWebAppTitle: String {
        String(localized: "Add a Web App…",
               comment: "Menu item and button where media players are offered: makes a website a Safari web app")
    }

    /// After the name of a web app whose site AutoHush hasn't been tested
    /// with, as a `HeadingBadge`.
    static var untestedBadge: String {
        String(localized: "Untested",
               comment: "Badge after the name of a Safari web app whose site AutoHush hasn't been tested with, where media players are offered")
    }

    /// After `webAppsHeading`, as a `HeadingBadge`.
    static var experimentalBadge: String {
        String(localized: "Experimental",
               comment: "Badge after the “Safari Web Apps” heading where media players are offered: web apps may not work as expected")
    }

    /// Under `webAppsHeading` wherever players are offered.
    static var webAppsNote: String {
        String(localized: "Every website works differently, so a web app may not pause or resume as expected.",
               comment: "Where media players are offered, under the “Safari Web Apps” heading and its “Experimental” badge")
    }

    /// In the "Add a Web App" and learning windows.
    static var webAppsWarning: String {
        String(localized: "Experimental: some websites may not pause or resume as expected.",
               comment: "Warning in the Add a Web App window and in the window that learns a web app's controls")
    }

    /// Instead of the players when none matches the search.
    static func noMatchNote(_ search: String) -> String {
        String(localized: "No players match “\(search)”.",
               comment: "Where media players are offered, when the search finds none; %@ is what was typed")
    }

    /// Under an app added with Add an App that's muted instead of paused,
    /// on its row in the menu (its tile says `mutedOnlyLabel`).
    static var mutedInsteadLabel: String {
        String(localized: "Muted instead of paused", comment: "The menu's rows of media players: under an app added with Add an App that no way could pause, so AutoHush mutes it while other apps play; and Settings → Diagnostics, under “Controlled by”")
    }

    /// Under an app added with Add an App that's muted instead of paused,
    /// on its tile (Settings → Media Player, the welcome window): a short
    /// `mutedInsteadLabel`.
    static var mutedOnlyLabel: String {
        String(localized: "Muted only", comment: "The tiles of media players (Settings → Media Player, the welcome window): under an app added with Add an App that no way could pause, so AutoHush mutes it instead while other apps play. Keep it short (about 12 characters)")
    }

    /// Under an app only its sound tells about (`needsAudioLevels`) while
    /// AntiDot mode is on, on its row in the menu: it can't be chosen
    /// (`antiDotModeReason` says why).
    static var antiDotModeLabel: String {
        String(localized: "Not in AntiDot mode", comment: "The menu's rows of media players: under an app added with Add an App that only its sound tells about (it can only be muted, or its Now Playing row doesn't show whether it plays), dimmed while AntiDot mode is on, which hears no sound (AntiDot mode, the detection that hides the purple recording indicator)")
    }

    /// The same on its tile (Settings → Media Player, the welcome window): a
    /// short `antiDotModeLabel`.
    static var antiDotModeTileLabel: String {
        String(localized: "Not in AntiDot", comment: "The tiles of media players (Settings → Media Player, the welcome window): under an app added with Add an App that only its sound tells about (it can only be muted, or its Now Playing row doesn't show whether it plays), dimmed while AntiDot mode is on, which hears no sound. Keep it short (about 14 characters at most)")
    }

    /// Where an app added with Add an App is removed: its tile's × (help tag,
    /// VoiceOver action) and its row's alternate in the menu (Option).
    static func removeTitle(_ name: String) -> String {
        String(localized: "Remove \(name)…", comment: "Removes an app added with Add an App from the media players, after asking: the menu's row with Option held, and the × on its tile (Settings → Media Player, the welcome window) as its help tag and VoiceOver action; %@ is the app")
    }

    /// Why it can't be chosen in AntiDot mode: the help tag and VoiceOver
    /// hint of its row and its tile, in the words the menu's card and
    /// Settings → Behavior use for the chosen player.
    var antiDotModeReason: String {
        pausesByMuting ? AntiDotText.onlyMuted(name) : AntiDotText.onlyHeard(name)
    }

    /// `SourceText.interruptsLabel(mutes:)`, for the views that still ask
    /// for it here.
    static func interruptsLabel(mutes: Bool) -> String { SourceText.interruptsLabel(mutes: mutes) }

    /// Under a player that isn't installed, wherever players are offered.
    static var notInstalledLabel: String {
        String(localized: "Not installed", comment: "Under a media player that isn't on this Mac")
    }

    /// Under a suggested web app, wherever players are offered: a click adds it.
    static var clickToAddLabel: String {
        String(localized: "Click to add", comment: "Under a suggested Safari web app wherever media players are offered (the menu's rows; the tiles in Settings → Media Player and the welcome window): a click adds it. Keep it short (about 12 characters): a plain “Add” is fine")
    }

    /// Where the chosen player is shown while none is (Settings → General,
    /// Diagnostics).
    static var noneChosenLabel: String {
        String(localized: "None chosen", comment: "Settings → General and Diagnostics: no media player chosen")
    }
}
