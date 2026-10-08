import Foundation

/// Makes a web app, an app of its own for a website, from an address the
/// user typed, so it can be chosen as the music player. The app shows the
/// steps; `AutoHushPlayers` provides the way (Safari's Add to Dock).
package protocol WebAppMaking: Sendable {
    /// Checks the address, asks the site whether it answers, opens it, then
    /// makes the web app once `confirmAdd` says the user wants it added
    /// (`false`: cancelled), reporting each step. Throws a
    /// `WebAppMakingError`.
    func makeWebApp(from address: String,
                    onStep: @escaping @Sendable (WebAppMakingStep) -> Void,
                    confirmAdd: @escaping @Sendable () async -> Bool) async throws -> MadeWebApp
}

/// A website suggested as a web app, such as a music service's web player:
/// offered with the players, to add, until a web app opens it.
package struct WebAppSuggestion: Equatable, Sendable {
    package let name: String
    /// What "Add a Web App" is filled in with, e.g. "music.youtube.com".
    package let address: String

    package init(name: String, address: String) {
        self.name = name
        self.address = address
    }
}

/// A step of making a web app, as it comes.
package enum WebAppMakingStep: Equatable, Sendable {
    /// The address is a web address, and the site answers.
    case checked
    /// The website is open in the browser.
    case opened
    /// The browser shows another site first (`shown`), asking something
    /// (cookies, signing in): the user answers it there, until `site` shows.
    case siteAsks(shown: String, site: String)
    /// `site` shows in the browser: it waits for the user to add it.
    case readyToAdd(site: String)
    /// Adding it with the browser.
    case adding
    /// The web app exists, made now or already there.
    case made(MadeWebApp)
}

/// The web app, ready to be chosen.
package struct MadeWebApp: Equatable, Sendable {
    package let bundleID: String
    package let name: String
    package let url: URL
    /// It was there already (the same website): nothing was made.
    package let alreadyThere: Bool

    package init(bundleID: String, name: String, url: URL, alreadyThere: Bool) {
        self.bundleID = bundleID
        self.name = name
        self.url = url
        self.alreadyThere = alreadyThere
    }
}

/// Why a web app couldn't be made.
package enum WebAppMakingError: Error, Equatable, Sendable {
    /// What was typed isn't a web address.
    case notAWebAddress
    /// The site didn't answer (no such host, no connection, a timeout).
    case noAnswer(host: String)
    /// The site answered that the page doesn't exist.
    case pageNotFound(host: String)
    /// The browser can't be driven without the Accessibility permission.
    case accessibilityDenied
    /// The browser didn't open the page, offer to add it, or make the app.
    case browserFailed(String)
}
