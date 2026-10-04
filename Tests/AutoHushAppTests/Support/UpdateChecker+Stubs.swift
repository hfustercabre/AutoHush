import Foundation
@testable import AutoHushApp

extension UpdateChecker {
    /// Answers like GitHub, with the tag `latest` gives at each check (e.g.
    /// "v0.3.0") as the latest release, with its disk image unless
    /// `diskImage` is false; `onFetch` runs before each answer.
    static func latestRelease(
        _ latest: @escaping @Sendable () -> String,
        diskImage: Bool = true,
        onFetch: @escaping @Sendable () async -> Void = {}
    ) -> UpdateChecker {
        UpdateChecker { request in
            await onFetch()
            let tag = latest()
            let version = tag.dropFirst()
            let assets = diskImage ? #"""
                [{"name": "AutoHush-\#(version).dmg",
                  "browser_download_url": "https://github.com/hfustercabre/AutoHush/releases/download/\#(tag)/AutoHush-\#(version).dmg",
                  "digest": "sha256:\#(String(repeating: "ab", count: 32))"}]
                """# : "[]"
            let body = #"{"tag_name": "\#(tag)", "html_url": "https://github.com/hfustercabre/AutoHush/releases/tag/\#(tag)", "assets": \#(assets)}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    /// Answers with `tag` as the latest release.
    static func latestRelease(_ tag: String, diskImage: Bool = true) -> UpdateChecker {
        latestRelease({ tag }, diskImage: diskImage)
    }

    /// A Mac without a network.
    static let offline = UpdateChecker { _ in throw URLError(.notConnectedToInternet) }
}
