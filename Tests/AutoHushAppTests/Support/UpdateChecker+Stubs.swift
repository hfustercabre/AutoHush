import Foundation
@testable import AutoHushApp

extension UpdateChecker {
    /// Answers like GitHub, with the tag `latest` gives at each check (e.g.
    /// "v0.3.0") as the latest release; `onFetch` runs before each answer.
    static func latestRelease(
        _ latest: @escaping @Sendable () -> String,
        onFetch: @escaping @Sendable () async -> Void = {}
    ) -> UpdateChecker {
        UpdateChecker { request in
            await onFetch()
            let tag = latest()
            let body = #"{"tag_name": "\#(tag)", "html_url": "https://github.com/hfustercabre/AutoHush/releases/tag/\#(tag)"}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    /// Answers with `tag` as the latest release.
    static func latestRelease(_ tag: String) -> UpdateChecker {
        latestRelease { tag }
    }

    /// A Mac without a network.
    static let offline = UpdateChecker { _ in throw URLError(.notConnectedToInternet) }
}
