import Testing
@testable import AutoHushKit

@Suite("CountrySites")
struct CountrySitesTests {
    /// A made-up service with Amazon Music's shape: two countries share a
    /// site, the United States has the one for everywhere else.
    private let sites = CountrySites(
        name: "Some Music",
        byRegion: ["US": "music.some.com", "GB": "music.some.co.uk", "IE": "music.some.co.uk",
                   "DE": "music.some.de", "AT": "music.some.de", "ES": "music.some.es"],
        elsewhere: "music.some.com"
    )

    @Test("a country's own site, else the one for every other country")
    func site() {
        #expect(sites.site(region: "ES") == "music.some.es")
        #expect(sites.site(region: "IE") == "music.some.co.uk")
        #expect(sites.site(region: "NL") == "music.some.com")
        #expect(sites.site(region: "") == "music.some.com")
        #expect(sites.site(region: nil) == "music.some.com")
        #expect(sites.hosts == ["music.some.co.uk", "music.some.com", "music.some.de", "music.some.es"])
    }

    @Test("an address as typed is one of its sites, with or without https, www or a path")
    func covers() {
        #expect(sites.covers(address: "music.some.es"))
        #expect(sites.covers(address: "https://www.music.some.de/home?x=1"))
        #expect(sites.covers(address: " Music.Some.COM "))
        #expect(!sites.covers(address: "www.some.es"))
        #expect(!sites.covers(address: "music.youtube.com"))
        #expect(!sites.covers(address: ""))
    }

    @Test("the country an address is for: the one picked, then the Mac's, then its ending, then the first by code")
    func country() {
        // The Mac's region, when the address is its site.
        #expect(sites.country(of: "music.some.es", preferring: ["ES"]) == "ES")
        // Picked last wins over the Mac's, while the address is its site.
        #expect(sites.country(of: "music.some.co.uk", preferring: ["IE", "ES"]) == "IE")
        #expect(sites.country(of: "music.some.co.uk", preferring: ["ES"]) == "GB")
        // A shared site typed: the country its host ends with, not Austria.
        #expect(sites.country(of: "music.some.de", preferring: ["ES"]) == "DE")
        #expect(sites.country(of: "music.some.de", preferring: ["AT"]) == "AT")
        // The site for everywhere else: the United States, unless the Mac's
        // region (or the pick) has no site of its own.
        #expect(sites.country(of: "music.some.com", preferring: ["ES"]) == "US")
        #expect(sites.country(of: "music.some.com", preferring: ["NL"]) == "")
        #expect(sites.country(of: "music.some.com", preferring: ["", "US"]) == "")
        #expect(sites.country(of: "music.some.com", preferring: []) == "US")
        // A pick whose site the address isn't any more: the address decides.
        #expect(sites.country(of: "music.some.es", preferring: ["IE", "US"]) == "ES")
    }
}
