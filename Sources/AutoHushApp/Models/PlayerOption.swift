import AppKit
import AutoHushKit

/// A music player as the menu, Settings and the welcome window offer it.
struct PlayerOption: Equatable, Identifiable {
    /// A suggested web app's is made up (`suggestionID(_:)`): it has none yet.
    let bundleID: String
    let name: String
    /// Where the app is installed; `nil` when it isn't, and then it can't be
    /// chosen.
    let appURL: URL?
    /// Shown in place of its icon while it isn't installed.
    var iconPlaceholder: PlayerIconPlaceholder?
    /// A supported app, an app added through a check, or a Safari web app:
    /// they're offered apart.
    var kind: MusicPlayerKind = .app
    /// A suggested web app's address: it isn't added yet, and a click opens
    /// "Add a Web App" filled in with it.
    var webAddress: String?
    /// A web app of a site AutoHush hasn't been tested with: offered last,
    /// marked "Untested".
    var isUntested = false
    /// An app added with Add an App that's muted instead of paused: said
    /// under its name.
    var pausesByMuting = false
    /// Only its sound level tells how it is: muted only, or controlled
    /// through a Now Playing row that doesn't follow it (Qobuz's).
    var needsAudioLevels = false
    /// An app added with Add an App that's a Chromium browser's web app (a
    /// Chrome app, a Brave app…): its browser's name, e.g. "Google Chrome".
    /// Its icon carries the browser's, and VoiceOver says it (`spokenName`).
    var browserName: String?
    /// AntiDot mode is on, and only this app's sound tells how it is
    /// (`needsAudioLevels`), which AntiDot mode never hears, so it can't be
    /// chosen. It's offered dimmed, saying why (`[PlayerOption].inAntiDotMode(_:)`
    /// sets it).
    var isUnavailableInAntiDotMode = false

    var id: String { bundleID }
    var isInstalled: Bool { appURL != nil }
    /// A click does something: chooses the player, or adds the suggested web
    /// app. Not in AntiDot mode for an app only its sound tells about.
    var isClickable: Bool { (isInstalled || webAddress != nil) && !isUnavailableInAntiDotMode }

    /// A player's placeholder is its own, so it doesn't tell options apart.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.bundleID == rhs.bundleID && lhs.name == rhs.name && lhs.appURL == rhs.appURL && lhs.kind == rhs.kind
            && lhs.webAddress == rhs.webAddress && lhs.isUntested == rhs.isUntested && lhs.pausesByMuting == rhs.pausesByMuting
            && lhs.needsAudioLevels == rhs.needsAudioLevels && lhs.browserName == rhs.browserName && lhs.isUnavailableInAntiDotMode == rhs.isUnavailableInAntiDotMode
    }

    /// A suggested web app, not added yet.
    static func suggestion(_ suggestion: WebAppSuggestion) -> PlayerOption {
        PlayerOption(bundleID: suggestionID(suggestion.address), name: suggestion.name, appURL: nil,
                     kind: .safariWebApp, webAddress: suggestion.address)
    }

    /// Stands for a suggested web app's bundle ID, which isn't known yet.
    static func suggestionID(_ address: String) -> String { "suggested-web-app:" + address }

    /// Finds an installed app by bundle ID.
    typealias Locate = @MainActor (String) -> URL?

    static let locateInstalledApp: Locate = {
        firstInstalled(NSWorkspace.shared.urlsForApplications(withBundleIdentifier: $0))
    }

    /// Where apps are installed: /Applications, the current user's
    /// Applications folder and /System/Applications. macOS also lists copies
    /// elsewhere, such as one in the Trash or on the disk image it came from.
    static let applicationFolders: [URL] = [
        URL(filePath: "/Applications", directoryHint: .isDirectory),
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory),
        URL(filePath: "/System/Applications", directoryHint: .isDirectory),
    ]

    /// The first app in one of `folders`, or a folder inside one, that is
    /// still on disk: macOS can list an app deleted moments ago until Launch
    /// Services catches up.
    static func firstInstalled(
        _ urls: [URL],
        in folders: [URL] = applicationFolders,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL? {
        urls.first { url in
            folders.contains { url.path.hasPrefix($0.path + "/") } && exists(url)
        }
    }

    /// Every player in the catalog, the Safari web apps found included, in
    /// its order, and where it is installed (where the player says, else
    /// where macOS knows it); then the suggested web apps not added yet. An
    /// app added through a check that's a Chromium browser's web app has
    /// its browser's name.
    @MainActor
    static func list(_ catalog: MusicPlayerCatalog, locate: Locate) -> [PlayerOption] {
        catalog.all.map {
            let appURL = $0.installedURL ?? locate($0.bundleID)
            return PlayerOption(bundleID: $0.bundleID, name: $0.name, appURL: appURL,
                                iconPlaceholder: $0.iconPlaceholder, kind: $0.kind, isUntested: $0.isUntested,
                                pausesByMuting: $0.pausesByMuting, needsAudioLevels: $0.needsAudioLevels,
                                browserName: $0.kind == .checkedApp ? appURL.flatMap(CheckableApp.browserName(ofAppAt:)) : nil)
        } + catalog.webAppSuggestions.map(suggestion)
    }

    /// The app's icon; its placeholder while it isn't installed; a download
    /// symbol for a suggested web app. A Safari web app's carries Safari's
    /// icon, so it isn't taken for an app of the same name.
    @MainActor
    func icon(size: CGFloat) -> NSImage {
        if webAddress != nil { return Self.downloadSymbol(size: size) }
        if appURL == nil, let iconPlaceholder {
            return AppIcon.image(placeholder: iconPlaceholder, id: bundleID, size: size)
        }
        switch kind {
        case .safariWebApp: return AppIcon.webAppImage(bundlePath: appURL?.path, size: size)
        case .checkedApp: return AppIcon.appImage(bundlePath: appURL?.path, size: size) // a browser's web app badged
        case .app: return AppIcon.image(bundlePath: appURL?.path, size: size)
        }
    }

    /// What VoiceOver says for it where players are offered: a web app
    /// named as one of `options`' apps is says it's one ("Spotify, Safari
    /// web app"), as its icon's Safari badge shows; an app added through a
    /// check that's a Chromium browser's web app always says whose
    /// ("SoundCloud, Google Chrome web app"), as its icon's badge shows.
    func spokenName(among options: [PlayerOption]) -> String {
        if kind == .checkedApp, let browserName {
            return String(localized: "\(name), \(browserName) web app",
                          comment: "VoiceOver, where media players are offered: an app added with Add an App that's a web app made by Chrome or another Chromium browser (its icon carries the browser's); the first %@ is its name, e.g. SoundCloud, the second the browser, e.g. Google Chrome")
        }
        guard kind == .safariWebApp,
              options.contains(where: { $0.kind != .safariWebApp && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame })
        else { return name }
        return String(localized: "\(name), Safari web app",
                      comment: "VoiceOver, where media players are offered: a Safari web app whose name is also an app's, told apart from it; %@ is its name, e.g. Spotify")
    }

    /// A download arrow in a circle, about as big as an app icon's artwork,
    /// in the text's color (a template).
    @MainActor
    static func downloadSymbol(size: CGFloat) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: size * 0.68, weight: .regular)
        let symbol = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let symbol else { return false }
            let drawn = symbol.size
            symbol.draw(in: NSRect(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2,
                                   width: drawn.width, height: drawn.height))
            return true
        }
        image.isTemplate = true
        return image
    }

    /// From this many players on, the menu and the welcome window offer a
    /// search over them (Settings shows every tile on a page that scrolls).
    static let searchThreshold = 8

    /// Over the players that are apps, before the Safari web apps, wherever
    /// players are offered.
    static var supportedAppsHeading: String {
        String(localized: "Supported Apps",
               comment: "Where media players are offered (the menu, Settings → General, the welcome window): heading over the players that are apps, before the “Safari Web Apps”")
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
               comment: "Where media players are offered (the menu, Settings → General, the welcome window): heading over the apps added through a check (Add an App…), after the “Supported Apps”")
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
        String(localized: "Web apps are experimental. Every website works differently, so AutoHush may not pause or resume one as expected.",
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
    /// on its tile (Settings → General, the welcome window): a short
    /// `mutedInsteadLabel`.
    static var mutedOnlyLabel: String {
        String(localized: "Muted only", comment: "The tiles of media players (Settings → General, the welcome window): under an app added with Add an App that no way could pause, so AutoHush mutes it instead while other apps play. Keep it short (about 12 characters)")
    }

    /// Under an app only its sound tells about (`needsAudioLevels`) while
    /// AntiDot mode is on, on its row in the menu: it can't be chosen
    /// (`antiDotModeReason` says why).
    static var antiDotModeLabel: String {
        String(localized: "Not in AntiDot mode", comment: "The menu's rows of media players: under an app added with Add an App that only its sound tells about (it can only be muted, or its Now Playing row doesn't show whether it plays), dimmed while AntiDot mode is on, which hears no sound (AntiDot mode, the detection that hides the purple recording indicator)")
    }

    /// The same on its tile (Settings → General, the welcome window): a
    /// short `antiDotModeLabel`.
    static var antiDotModeTileLabel: String {
        String(localized: "Not in AntiDot", comment: "The tiles of media players (Settings → General, the welcome window): under an app added with Add an App that only its sound tells about (it can only be muted, or its Now Playing row doesn't show whether it plays), dimmed while AntiDot mode is on, which hears no sound. Keep it short (about 14 characters at most)")
    }

    /// Where an app added with Add an App is removed: its tile's × (help tag,
    /// VoiceOver action) and its row's alternate in the menu (Option).
    static func removeTitle(_ name: String) -> String {
        String(localized: "Remove \(name)…", comment: "Removes an app added with Add an App from the media players, after asking: the menu's row with Option held, and the × on its tile (Settings → General, the welcome window) as its help tag and VoiceOver action; %@ is the app")
    }

    /// Why it can't be chosen in AntiDot mode: the help tag and VoiceOver
    /// hint of its row and its tile.
    var antiDotModeReason: String {
        pausesByMuting
            ? String(localized: "AutoHush can only mute it, and muting needs Audio Recording, which AntiDot mode doesn’t use.",
                     comment: "Help tag and VoiceOver hint of an app added with Add an App that can only be muted, where media players are offered, dimmed while AntiDot mode is on")
            : String(localized: "Only its sound tells AutoHush whether it plays, and hearing it needs Audio Recording, which AntiDot mode doesn’t use.",
                     comment: "Help tag and VoiceOver hint of an app added with Add an App whose Now Playing row doesn't show whether it plays, where media players are offered, dimmed while AntiDot mode is on")
    }

    /// Under an app that pauses the player while it plays (the menu's Playing
    /// Now, Settings → Apps), or mutes it, for one muted instead of paused.
    static func interruptsLabel(mutes: Bool) -> String {
        mutes ? String(localized: "Mutes your player", comment: "The menu's Playing Now and Settings → Apps: under an app that mutes your player while it plays (a player added with Add an App that can only be muted)")
            : String(localized: "Pauses your player", comment: "The menu's Playing Now and Settings → Apps: under an app that pauses your player while it plays")
    }

    /// Under a player that isn't installed, wherever players are offered.
    static var notInstalledLabel: String {
        String(localized: "Not installed", comment: "Under a media player that isn't on this Mac")
    }

    /// Under a suggested web app, wherever players are offered: a click adds it.
    static var clickToAddLabel: String {
        String(localized: "Click to add", comment: "Under a suggested Safari web app wherever media players are offered (the menu's rows; the tiles in Settings → General and the welcome window): a click adds it. Keep it short (about 12 characters): a plain “Add” is fine")
    }

    /// Where the chosen player is shown while none is (Settings → General,
    /// Diagnostics).
    static var noneChosenLabel: String {
        String(localized: "None chosen", comment: "Settings → General and Diagnostics: no media player chosen")
    }

    /// Shown in Settings and the welcome window while no supported player is
    /// installed.
    static var noneInstalledWarning: String {
        String(localized: "No supported media player is installed. Install one of these, or add another app under Other Apps, and choose it here.",
               comment: "Settings and the welcome window, while none of the media players is installed; “Other Apps” is the heading over the apps added with Add an App… (its Add… tile)")
    }

    /// In the welcome window when one player is installed and others could
    /// be, e.g. "Spotify is the only supported media player on this Mac.
    /// AutoHush also works with Apple Music and VLC."; `nil` otherwise.
    static func onlyInstalledNote(among options: [PlayerOption]) -> String? {
        guard let only = options.onlyInstalled else { return nil }
        let others = options.filter { !$0.isInstalled && $0.kind == .app }.map(\.name)
        guard !others.isEmpty else { return nil }
        let list = others.formatted(.list(type: .and))
        return String(localized: "\(only.name) is the only supported media player on this Mac. AutoHush also works with \(list).",
                      comment: "Welcome window; the installed media player, then the other supported ones, e.g. “Apple Music and VLC”")
    }
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

    /// Where the Safari web apps start, for their heading; `nil` without any.
    var webAppsStart: Int? {
        firstIndex { $0.kind == .safariWebApp }
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

    /// No supported player is installed: none can be chosen.
    var noneInstalled: Bool { !contains(where: \.isInstalled) }

    /// The one installed player, when exactly one is.
    var onlyInstalled: PlayerOption? {
        let installed = filter(\.isInstalled)
        return installed.count == 1 ? installed[0] : nil
    }
}
