import Foundation
import AutoHushKit

/// A music service's web player that AutoHush offers as a web app, to add,
/// until one of the Mac's web apps opens it.
package struct SuggestedWebApp: Equatable, Sendable {
    package let name: String
    /// Its address, e.g. "music.youtube.com".
    package let address: String
    /// The other hosts its web app may open, e.g. the service's sites for
    /// other countries.
    package let otherHosts: [String]

    package init(name: String, address: String, otherHosts: [String] = []) {
        self.name = name
        self.address = address
        self.otherHosts = otherHosts
    }

    /// Whether `app` opens it: its address's host, or one of the others.
    package func isAdded(as app: SafariWebApp) -> Bool {
        let host = WebAddress.url(from: address)?.host()
        return ([host].compactMap { $0 } + otherHosts).contains(where: app.opens(host:))
    }

    /// Those of `suggested` that none of `apps` opens, as the catalog offers them.
    package static func notAdded(_ suggested: [SuggestedWebApp], among apps: [SafariWebApp]) -> [WebAppSuggestion] {
        suggested
            .filter { suggestion in !apps.contains(where: suggestion.isAdded(as:)) }
            .map { WebAppSuggestion(name: $0.name, address: $0.address) }
    }
}
