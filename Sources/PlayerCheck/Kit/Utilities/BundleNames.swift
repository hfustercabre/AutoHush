import AppKit
import AutoHushKit
import WebAppPlayers

/// An app's name as Finder shows it (`AppName`), by its bundle ID,
/// wherever Launch Services finds it: a Chromium web app's browser, say
/// ("Google Chrome").
package enum BundleNames {
    package static func name(of bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map(AppName.of(appAt:)) ?? bundleID
    }

    /// What a Safari web app's bundle ID starts with (`SafariWebApp`'s), for
    /// the Player Check app.
    package static let safariWebAppPrefix = SafariWebApp.bundleIDPrefix
}
