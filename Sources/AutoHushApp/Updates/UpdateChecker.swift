import Foundation

/// A dotted numeric version such as "0.3.0" (a leading "v" is accepted).
struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    let components: [Int]

    init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespaces)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        components = parts.compactMap { $0 }
    }

    var description: String { components.map(String.init).joined(separator: ".") }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        let left = lhs.components + Array(repeating: 0, count: count - lhs.components.count)
        let right = rhs.components + Array(repeating: 0, count: count - rhs.components.count)
        return left.lexicographicallyPrecedes(right)
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    /// The running app's `CFBundleShortVersionString`.
    static var current: AppVersion? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
    }
}

/// A published release: its version, its GitHub page, its notes and, when it
/// has one, the disk image AutoHush installs it from.
struct AppRelease: Equatable, Sendable {
    /// The release's `AutoHush-<version>.dmg`, as GitHub lists it.
    struct DiskImage: Equatable, Sendable {
        let url: URL
        /// Hex SHA-256 of the file, when GitHub reports one.
        let sha256: String?
    }

    let version: AppVersion
    let pageURL: URL
    let diskImage: DiskImage?
    /// What's new, in Markdown: the release's CHANGELOG section.
    let notes: String?

    init(version: AppVersion, pageURL: URL, diskImage: DiskImage? = nil, notes: String? = nil) {
        self.version = version
        self.pageURL = pageURL
        self.diskImage = diskImage
        self.notes = notes
    }
}

/// What an update check found.
enum UpdateCheckResult: Equatable, Sendable {
    case upToDate(latest: AppVersion)
    case available(AppRelease)
    /// The repository has no published release yet.
    case noReleases
}

/// Why an update check could not tell.
enum UpdateCheckError: LocalizedError, Equatable {
    case badResponse(Int)
    case unreadableRelease

    var errorDescription: String? {
        switch self {
        case .badResponse(let status):
            return String(localized: "GitHub answered with HTTP status \(status).",
                          comment: "Update check error; %lld is an HTTP status code")
        case .unreadableRelease:
            return String(localized: "GitHub's release information could not be read.", comment: "Update check error")
        }
    }
}

/// Asks GitHub for the latest published release. Only `api.github.com` is
/// contacted, and only the release's tag, page URL, notes and disk image are
/// read.
/// The page URL is the only thing AutoHush ever opens from an answer, so it
/// must be one of this repository's release pages on github.com; the disk
/// image must be one of its release downloads, or the release has none.
struct UpdateChecker: Sendable {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let fetch: Fetch

    init(fetch: @escaping Fetch = { try await URLSession.shared.data(for: $0) }) {
        self.fetch = fetch
    }

    func check(currentVersion: AppVersion) async throws -> UpdateCheckResult {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(ProjectInfo.repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await fetch(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return .noReleases }
        guard status == 200 else { throw UpdateCheckError.badResponse(status) }

        /// The fields read from GitHub's answer.
        struct Release: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
                /// E.g. "sha256:3734f1d8…"; missing from older answers.
                let digest: String?
            }
            let tag_name: String
            let html_url: URL
            /// The release notes, in Markdown.
            let body: String?
            let assets: [Asset]?
        }
        guard let release = try? JSONDecoder().decode(Release.self, from: data),
              let latest = AppVersion(release.tag_name),
              Self.isReleasePage(release.html_url)
        else { throw UpdateCheckError.unreadableRelease }

        guard latest > currentVersion else { return .upToDate(latest: latest) }
        let diskImage = release.assets?
            .first { $0.name == "AutoHush-\(latest).dmg" && Self.isReleaseDownload($0.browser_download_url) }
            .map { AppRelease.DiskImage(url: $0.browser_download_url, sha256: Self.sha256(fromDigest: $0.digest)) }
        let notes = release.body?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .available(AppRelease(version: latest, pageURL: release.html_url, diskImage: diskImage,
                                     notes: notes?.isEmpty == false ? notes : nil))
    }

    /// True for a release page of this repository on github.com, over HTTPS:
    /// never another site, a file, a network share or another app's scheme.
    static func isReleasePage(_ url: URL) -> Bool {
        url.scheme == "https" && url.host() == "github.com"
            && url.standardized.path().hasPrefix("/\(ProjectInfo.repository)/releases/")
    }

    /// True for a file published with one of this repository's releases.
    static func isReleaseDownload(_ url: URL) -> Bool {
        isReleasePage(url) && url.standardized.path().hasPrefix("/\(ProjectInfo.repository)/releases/download/")
    }

    /// The hex SHA-256 in a digest such as "sha256:3734f1d8…", or nil for
    /// another algorithm or a malformed digest.
    static func sha256(fromDigest digest: String?) -> String? {
        guard let digest, digest.hasPrefix("sha256:") else { return nil }
        let hex = digest.dropFirst("sha256:".count).lowercased()
        return hex.count == 64 && hex.allSatisfy(\.isHexDigit) ? hex : nil
    }

    /// True when AutoHush was installed with the Homebrew cask.
    static var isHomebrewInstall: Bool {
        ["/opt/homebrew/Caskroom/autohush", "/usr/local/Caskroom/autohush"]
            .contains { FileManager.default.fileExists(atPath: $0) }
    }
}
