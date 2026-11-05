import Foundation
import AutoHushKit

/// The Safari web apps on this Mac as players, each kept as long as it's
/// installed: a player remembers its button and how learning goes.
package final class SafariWebAppPlayers: Sendable {
    private let finder: SafariWebAppFinder
    private let tested: [TestedWebApp]
    private let makePlayer: @Sendable (SafariWebApp, _ isUntested: Bool) -> SafariWebAppPlayer
    private let players = KeptPlayers<SafariWebApp, SafariWebAppPlayer>(key: { $0.bundleID }, source: { $0.app })

    /// `tested`: the sites AutoHush has been tested with; any other web app
    /// is untested.
    package init(
        finder: SafariWebAppFinder = SafariWebAppFinder(),
        tested: [TestedWebApp] = [],
        makePlayer: @escaping @Sendable (SafariWebApp, _ isUntested: Bool) -> SafariWebAppPlayer = { app, isUntested in
            // With its backups on (the Play/Pause key, the Now Playing panel), a refused pause is
            // left to AutoHush's mute, which tries them meanwhile (the user, 2026-11-05).
            SafariWebAppPlayer(app: app, isUntested: isUntested,
                               mutesRefusals: { !BackupSwitchesStore().switches(for: app.bundleID).usesBackups })
        }
    ) {
        self.finder = finder
        self.tested = tested
        self.makePlayer = makePlayer
    }

    /// One player for each web app installed now, by name; a tested site's
    /// is named as the site ("YouTube Music", whatever Safari called it). A
    /// web app that was renamed or moved gets a new one.
    package func current() -> [SafariWebAppPlayer] {
        let apps = finder.webApps().map(named).sorted { $0.name.localizedLowercase < $1.name.localizedLowercase }
        return players.current(apps) { app in makePlayer(app, !tested.contains { $0.isAdded(as: app) }) }
    }

    /// `app`, named as its tested site when it's one's.
    private func named(_ app: SafariWebApp) -> SafariWebApp {
        guard let site = tested.first(where: { $0.isAdded(as: app) }), site.name != app.name else { return app }
        return SafariWebApp(bundleID: app.bundleID, name: site.name, url: app.url, startURL: app.startURL)
    }

    /// The tested sites that no web app installed now opens, to suggest.
    package func suggestions() -> [WebAppSuggestion] {
        TestedWebApp.notAdded(tested, among: finder.webApps())
    }
}
