import Foundation
import Network
import os

/// What the user typed as a website's address, made into one, and the site
/// asked whether it answers: for making a web app (`WebAppMaking`) and for
/// a service's sites by country (`CountrySites`).
package enum WebAddress {
    /// The web address in `text`: http or https, with a host that has a dot
    /// (or is localhost), and no spaces. Without a scheme at its start,
    /// "https://" is added: "music.youtube.com" is https://music.youtube.com,
    /// even with an address in its query ("radio.example.com/?next=https://…").
    package static func url(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let hasScheme = trimmed.range(of: "^[A-Za-z][A-Za-z0-9+.-]*://", options: .regularExpression) != nil
        let withScheme = hasScheme ? trimmed : "https://" + trimmed
        guard let components = URLComponents(string: withScheme),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              host == "localhost" || (host.contains(".") && !host.hasPrefix(".") && !host.hasSuffix(".")),
              let url = components.url
        else { return nil }
        return url
    }

    /// The host without a leading "www.", to compare sites.
    package static func siteHost(_ host: String) -> String {
        let lower = host.lowercased()
        return lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
    }

    /// Whether the page shown is the site at `typed`, rather than another
    /// one asking something first: the same host (with or without "www."),
    /// a part of the site (listen.example.com for example.com), or the same
    /// service in another place (music.example.es for music.example.com: the
    /// same first two parts, then only a place's ending, see `isPlaceEnding`).
    /// Another part of the same domain is another site (consent.example.com
    /// for music.example.com, accounts.example.com for open.example.com).
    /// Without hosts to compare, it counts as the site.
    package static func isSameSite(_ shown: URL, as typed: URL) -> Bool {
        guard let shownHost = shown.host(), !shownHost.isEmpty, let typedHost = typed.host() else { return true }
        let page = siteHost(shownHost)
        let site = siteHost(typedHost)
        if page == site || page.hasSuffix("." + site) { return true }
        let pageParts = page.split(separator: ".")
        let siteParts = site.split(separator: ".")
        return pageParts.count >= 3 && siteParts.count >= 3 && pageParts.prefix(2) == siteParts.prefix(2)
            && isPlaceEnding(pageParts.dropFirst(2)) && isPlaceEnding(siteParts.dropFirst(2))
    }

    /// Whether a host ends the way a service's sites for different places
    /// do: com, a country's code (es, de), the same after co or com (co.uk,
    /// com.br), or the ending of a region, nation or city (`placeEndings`:
    /// cat for Catalonia, berlin). Not any short ending (bad.co), nor an IP
    /// address.
    static func isPlaceEnding(_ labels: ArraySlice<Substring>) -> Bool {
        let isCountry: (Substring) -> Bool = { $0.count == 2 && $0.allSatisfy { $0.isASCII && $0.isLetter } }
        guard let last = labels.last else { return false }
        switch labels.count {
        case 1: return last == "com" || isCountry(last) || placeEndings.contains(String(last))
        case 2: return ["co", "com"].contains(labels.first!) && isCountry(last)
        default: return false
        }
    }

    /// Internet endings that stand for a place rather than a country: regions,
    /// nations and cultures, then cities.
    static let placeEndings: Set<String> = [
        "cat", "eus", "gal", "bzh", "scot", "wales", "cymru", "quebec", "bayern", "nrw", "ruhr", "saarland",
        "tirol", "alsace", "corsica", "frl", "vlaanderen", "swiss", "tatar", "krd", "africa", "asia", "lat", "arab",
        "berlin", "hamburg", "koeln", "cologne", "wien", "london", "paris", "amsterdam", "barcelona", "bcn",
        "madrid", "brussels", "gent", "zuerich", "stockholm", "helsinki", "budapest", "moscow", "istanbul", "ist",
        "tokyo", "kyoto", "nagoya", "okinawa", "osaka", "yokohama", "ryukyu", "taipei", "sydney", "melbourne",
        "capetown", "durban", "joburg", "nyc", "boston", "miami", "vegas", "rio", "abudhabi", "dubai", "doha",
    ]

    /// Asks the site once whether it answers, without cookies or a cache
    /// (an ephemeral session). Any answer counts but "not found"; a site
    /// that refuses a HEAD request is asked with GET.
    ///
    /// App Transport Security keeps URLSession from loading plain http, and
    /// AutoHush has no exception (one would weaken every load), while Safari
    /// opens such a site all the same (2026-10-19). So an http site answers
    /// when a connection to its host and port opens (`connects`), and an
    /// https site that sends AutoHush to http has answered with that.
    package static func checkAnswers(_ url: URL, session: URLSession = WebAddress.session,
                                     connects: @Sendable (URL) async -> Bool = { await WebAddress.connects(to: $0) }) async throws {
        let host = url.host() ?? url.absoluteString
        if url.scheme?.lowercased() == "http" {
            guard await connects(url) else { throw WebAppMakingError.noAnswer(host: host) }
            return
        }
        for method in ["HEAD", "GET"] {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
            request.httpMethod = method
            let response: URLResponse
            do {
                (_, response) = try await session.data(for: request, delegate: StopsAtPlainHTTP())
            } catch let error as URLError where error.code == .appTransportSecurityRequiresSecureConnection {
                return // sent to http, which App Transport Security wouldn't follow: it answered
            } catch {
                throw WebAppMakingError.noAnswer(host: host)
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            if status == 405 || status == 501, method == "HEAD" { continue } // HEAD not allowed: ask with GET
            if status == 404 || status == 410 { throw WebAppMakingError.pageNotFound(host: host) }
            return
        }
    }

    /// No cookies, no cache, nothing kept on the Mac.
    static let session = URLSession(configuration: .ephemeral)

    /// Whether a connection to `url`'s host and port (80 unless given)
    /// opens within `timeout`. Network.framework's connections aren't
    /// subject to App Transport Security.
    static func connects(to url: URL, timeout: TimeInterval = 10) async -> Bool {
        guard let host = url.host(), !host.isEmpty,
              let port = NWEndpoint.Port(rawValue: UInt16(clamping: url.port ?? 80)), port.rawValue != 0 else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        let queue = DispatchQueue(label: "AutoHush.WebAddress.connection")
        let answered = OSAllocatedUnfairLock(initialState: false)
        return await withCheckedContinuation { continuation in
            // Told once: open, refused or unreachable, or out of time.
            let tell: @Sendable (Bool) -> Void = { opened in
                guard answered.withLock({ told in defer { told = true }; return !told }) else { return }
                connection.cancel()
                continuation.resume(returning: opened)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: tell(true)
                // Waiting: refused, or no route to it now.
                case .waiting, .failed, .cancelled: tell(false)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { tell(false) }
        }
    }

    /// Doesn't follow a redirect to plain http, which App Transport
    /// Security would refuse: the redirect itself is the site's answer.
    final class StopsAtPlainHTTP: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            Self.follows(request)
        }

        /// `request`, unless it goes to plain http.
        static func follows(_ request: URLRequest) -> URLRequest? {
            request.url?.scheme?.lowercased() == "http" ? nil : request
        }
    }
}
