import AppKit
import AutoHushKit

/// A media player as the menu, Settings and the welcome window offer it.
struct PlayerOption: Equatable, Identifiable {
    /// A suggested web app's is made up (`suggestionID(_:)`): it has none yet.
    let bundleID: String
    let name: String
    /// Where the app is installed; `nil` when it isn't, and then it can't be
    /// chosen.
    let appURL: URL?
    /// Shown in place of its icon while it isn't installed. A player's
    /// placeholder is its own, so it doesn't tell options apart.
    @EqualityIgnored var iconPlaceholder: PlayerIconPlaceholder? = nil
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
    /// through a Now Playing row that doesn't follow it.
    var needsAudioLevels = false
    /// AutoHush can fade it (`MusicPlayer.canFade`); chosen, the fade
    /// settings are dimmed when it can't.
    var canFade = true
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

    /// The first app in one of `folders`, or a folder inside one, that is
    /// still on disk: macOS can list an app deleted moments ago until Launch
    /// Services catches up.
    static func firstInstalled(
        _ urls: [URL],
        in folders: [URL] = ApplicationFolders.all,
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
                                pausesByMuting: $0.pausesByMuting, needsAudioLevels: $0.needsAudioLevels, canFade: $0.canFade,
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
    /// named as one of `options`' apps says it's one ("Jukebox, Safari web
    /// app"), as its icon's Safari badge shows; an app added through a
    /// check that's a Chromium browser's web app always says whose
    /// ("Jukebox, Google Chrome web app"), as its icon's badge shows.
    func spokenName(among options: [PlayerOption]) -> String {
        if kind == .checkedApp, let browserName {
            return String(localized: "\(name), \(browserName) web app",
                          comment: "VoiceOver, where media players are offered: an app added with Add an App that's a web app made by Chrome or another Chromium browser (its icon carries the browser's); the first %@ is its name, the second the browser, e.g. Google Chrome")
        }
        guard kind == .safariWebApp,
              options.contains(where: { $0.kind != .safariWebApp && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame })
        else { return name }
        return String(localized: "\(name), Safari web app",
                      comment: "VoiceOver, where media players are offered: a Safari web app whose name is also an app's, told apart from it; %@ is its name")
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
}
