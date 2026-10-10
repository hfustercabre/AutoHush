import Foundation
import AutoHushKit

/// A music service's web player that AutoHush has been tested with. Its web
/// app is offered first; until one is added, the site is suggested (with a
/// download symbol). Any other web app is offered after them, marked
/// untested.
package struct TestedWebApp: Equatable, Sendable {
    package let name: String
    /// Its address, e.g. "music.youtube.com".
    package let address: String
    /// The other hosts its web app may open, e.g. the service's sites for
    /// other countries.
    package let otherHosts: [String]
    /// Its sites by country, when it has its own in some (Amazon Music).
    package let countrySites: CountrySites?

    package init(name: String, address: String, otherHosts: [String] = [], countrySites: CountrySites? = nil) {
        self.name = name
        self.address = address
        self.otherHosts = otherHosts
        self.countrySites = countrySites
    }

    /// A service with its own site in some countries: suggested on the site
    /// for `region` (the Mac's), and any of its sites counts as it.
    package init(countrySites: CountrySites, region: String?) {
        self.init(name: countrySites.name, address: countrySites.site(region: region),
                  otherHosts: countrySites.hosts, countrySites: countrySites)
    }

    /// Its address's host, then the others.
    var hosts: [String] {
        [WebAddress.url(from: address)?.host()].compactMap { $0 } + otherHosts
    }

    /// Whether `app` opens it: its address's host, or one of the others.
    package func isAdded(as app: SafariWebApp) -> Bool {
        hosts.contains(where: app.opens(host:))
    }

    /// Whether `url` is on its site (with or without "www.").
    package func covers(_ url: URL) -> Bool {
        guard let host = url.host() else { return false }
        return hosts.contains { WebAddress.siteHost($0) == WebAddress.siteHost(host) }
    }

    /// Those of `tested` that none of `apps` opens, to suggest.
    package static func notAdded(_ tested: [TestedWebApp], among apps: [SafariWebApp]) -> [WebAppSuggestion] {
        tested
            .filter { site in !apps.contains(where: site.isAdded(as:)) }
            .map { WebAppSuggestion(name: $0.name, address: $0.address) }
    }

    /// Whether `app` and `url` are the same service: the same site, or two
    /// of one tested service's sites (Amazon Music's in two countries).
    package static func sameSite(_ app: SafariWebApp, _ url: URL, tested: [TestedWebApp]) -> Bool {
        app.opens(url) || tested.contains { $0.covers(url) && $0.isAdded(as: app) }
    }
}
