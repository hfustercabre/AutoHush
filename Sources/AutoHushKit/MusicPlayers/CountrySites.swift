import Foundation

/// A web player with its own site in some countries, where a sign-in works
/// only on the site of the account's country (Amazon Music's
/// music.amazon.de for Germany and Austria): Add a Web App offers its sites
/// by country.
package struct CountrySites: Equatable, Sendable {
    /// The service's name, e.g. "Amazon Music".
    package let name: String
    /// Each country's site, by region code: "DE": "music.amazon.de".
    package let byRegion: [String: String]
    /// The site for every other country.
    package let elsewhere: String

    package init(name: String, byRegion: [String: String], elsewhere: String) {
        self.name = name
        self.byRegion = byRegion
        self.elsewhere = elsewhere
    }

    /// The site for `region` (a region code, e.g. "ES"): its own, or the
    /// one for every other country (also for `nil` or "").
    package func site(region: String?) -> String {
        region.flatMap { byRegion[$0] } ?? elsewhere
    }

    /// Every site, once each.
    package var hosts: [String] {
        Set(byRegion.values).union([elsewhere]).sorted()
    }

    /// Whether `address`, as typed (with or without "https://" or "www.", a
    /// path or not), is one of its sites.
    package func covers(address: String) -> Bool {
        Self.host(of: address).map(hosts.contains) ?? false
    }

    /// The country `address` is the site of, as a region code; "" for every
    /// other country. The first of `preferred` (the one picked last, then the
    /// Mac's region) whose site it is; else the country its host ends with
    /// (DE for music.amazon.de, though Austria uses it too); else the first
    /// whose site it is, by code.
    package func country(of address: String, preferring preferred: [String]) -> String {
        guard let host = Self.host(of: address) else { return "" }
        // A region without a site of its own stands for every other country.
        let known = preferred.map { byRegion[$0] == nil ? "" : $0 }
        if let match = known.first(where: { site(region: $0) == host }) { return match }
        if let ending = host.split(separator: ".").last.map({ $0.uppercased() }), byRegion[ending] == host { return ending }
        return byRegion.keys.sorted().first { byRegion[$0] == host } ?? ""
    }

    /// The host of an address as typed, lowercased, without "www.".
    static func host(of address: String) -> String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let host = URLComponents(string: url)?.host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
