import Foundation
import AutoHushKit

/// What the user typed as a website's address, made into one, and the site
/// asked whether it answers.
package enum WebAddress {
    /// The web address in `text`: http or https, with a host that has a dot
    /// (or is localhost), and no spaces. Without a scheme, "https://" is
    /// added: "music.youtube.com" is https://music.youtube.com.
    package static func url(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let components = URLComponents(string: withScheme),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              host == "localhost" || (host.contains(".") && !host.hasPrefix(".") && !host.hasSuffix(".")),
              let url = components.url
        else { return nil }
        return url
    }

    /// The host without a leading "www.", to compare sites.
    static func siteHost(_ host: String) -> String {
        let lower = host.lowercased()
        return lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
    }

    /// Asks the site once whether it answers, without cookies or a cache
    /// (an ephemeral session). Any answer counts but "not found"; a site
    /// that refuses a HEAD request is asked with GET.
    package static func checkAnswers(_ url: URL, session: URLSession = WebAddress.session) async throws {
        let host = url.host() ?? url.absoluteString
        for method in ["HEAD", "GET"] {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
            request.httpMethod = method
            let response: URLResponse
            do {
                (_, response) = try await session.data(for: request)
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
    package static let session = URLSession(configuration: .ephemeral)
}
