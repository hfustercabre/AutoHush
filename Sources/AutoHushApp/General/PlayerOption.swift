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
    /// An app, or a Safari web app: they're offered apart.
    var kind: MusicPlayerKind = .app
    /// A suggested web app's address: it isn't added yet, and a click opens
    /// "Add a Web App" filled in with it.
    var webAddress: String?
    /// A web app of a site AutoHush hasn't been tested with: offered last,
    /// marked "Untested".
    var isUntested = false

    var id: String { bundleID }
    var isInstalled: Bool { appURL != nil }
    /// A click does something: chooses the player, or adds the suggested web app.
    var isClickable: Bool { isInstalled || webAddress != nil }

    /// A player's placeholder is its own, so it doesn't tell options apart.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.bundleID == rhs.bundleID && lhs.name == rhs.name && lhs.appURL == rhs.appURL && lhs.kind == rhs.kind
            && lhs.webAddress == rhs.webAddress && lhs.isUntested == rhs.isUntested
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
    /// where macOS knows it); then the suggested web apps not added yet.
    @MainActor
    static func list(_ catalog: MusicPlayerCatalog, locate: Locate) -> [PlayerOption] {
        catalog.all.map {
            PlayerOption(bundleID: $0.bundleID, name: $0.name, appURL: $0.installedURL ?? locate($0.bundleID),
                         iconPlaceholder: $0.iconPlaceholder, kind: $0.kind, isUntested: $0.isUntested)
        } + catalog.webAppSuggestions.map(suggestion)
    }

    /// The app's icon; its placeholder while it isn't installed; a download
    /// symbol for a suggested web app.
    @MainActor
    func icon(size: CGFloat) -> NSImage {
        if webAddress != nil { return Self.downloadSymbol(size: size) }
        if appURL == nil, let iconPlaceholder {
            return AppIcon.image(placeholder: iconPlaceholder, id: bundleID, size: size)
        }
        return AppIcon.image(bundlePath: appURL?.path, size: size)
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

    /// From this many players on, every place that offers them has a search.
    static let searchThreshold = 8

    /// Over the Safari web apps, after the apps, wherever players are offered.
    static var webAppsHeading: String {
        String(localized: "Safari Web Apps",
               comment: "Where music players are offered: heading over the websites added to the Dock from Safari")
    }

    /// Where players are offered: the entry that adds a Safari web app.
    static var addWebAppTitle: String {
        String(localized: "Add a Web App…",
               comment: "Menu item and button where music players are offered: makes a website a Safari web app")
    }

    /// After the name of a web app whose site AutoHush hasn't been tested
    /// with, as a `HeadingBadge`.
    static var untestedBadge: String {
        String(localized: "Untested",
               comment: "Badge after the name of a Safari web app whose site AutoHush hasn't been tested with, where music players are offered")
    }

    /// After `webAppsHeading`, as a `HeadingBadge`.
    static var experimentalBadge: String {
        String(localized: "Experimental",
               comment: "Badge after the “Safari Web Apps” heading where music players are offered: web apps may not work as expected")
    }

    /// Under `webAppsHeading` wherever players are offered.
    static var webAppsNote: String {
        String(localized: "Every website works differently, so a web app may not pause or resume as expected.",
               comment: "Where music players are offered, under the “Safari Web Apps” heading and its “Experimental” badge")
    }

    /// In the "Add a Web App" and learning windows.
    static var webAppsWarning: String {
        String(localized: "Web apps are experimental. Every website works differently, so AutoHush may not pause or resume one as expected.",
               comment: "Warning in the Add a Web App window and in the window that learns a web app's controls")
    }

    /// Instead of the players when none matches the search.
    static func noMatchNote(_ search: String) -> String {
        String(localized: "No players match “\(search)”.",
               comment: "Where music players are offered, when the search finds none; %@ is what was typed")
    }

    /// Under a player that isn't installed, wherever players are offered.
    static var notInstalledLabel: String {
        String(localized: "Not installed", comment: "Under a music player that isn't on this Mac")
    }

    /// Shown in Settings and the welcome window while no supported player is
    /// installed.
    static var noneInstalledWarning: String {
        String(localized: "No supported music player is installed. Install one of these, and choose it here.",
               comment: "Settings and the welcome window, while none of the music players is installed")
    }

    /// In the welcome window when one player is installed and others could
    /// be, e.g. "Spotify is the only supported music player on this Mac.
    /// AutoHush also works with Apple Music and VLC."; `nil` otherwise.
    static func onlyInstalledNote(among options: [PlayerOption]) -> String? {
        guard let only = options.onlyInstalled else { return nil }
        let others = options.filter { !$0.isInstalled && $0.kind == .app }.map(\.name)
        guard !others.isEmpty else { return nil }
        let list = others.formatted(.list(type: .and))
        return String(localized: "\(only.name) is the only supported music player on this Mac. AutoHush also works with \(list).",
                      comment: "Welcome window; the installed music player, then the other supported ones, e.g. “Apple Music and VLC”")
    }
}

extension [PlayerOption] {
    /// How players are offered: the apps, installed ones first, then the
    /// Safari web apps (`PlayerOption.webAppsHeading` goes over them): those
    /// of tested sites, the tested sites not added yet, then the untested
    /// ones; each group in the catalog's order.
    var offered: [PlayerOption] {
        let apps = filter { $0.kind == .app }
        let webApps = filter { $0.kind == .safariWebApp }
        return apps.filter(\.isInstalled) + apps.filter { !$0.isInstalled }
            + webApps.filter { $0.webAddress == nil && !$0.isUntested } + webApps.filter { $0.webAddress != nil }
            + webApps.filter(\.isUntested)
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
