import Foundation
import AutoHushKit

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

struct AppRelease: Equatable, Sendable {
    let version: AppVersion
    let pageURL: URL
}

enum UpdateCheckResult: Equatable, Sendable {
    case upToDate(latest: AppVersion)
    case available(AppRelease)
    /// The repository has no published release yet.
    case noReleases
}

enum UpdateCheckError: LocalizedError, Equatable {
    case badResponse(Int)
    case unreadableRelease

    var errorDescription: String? {
        switch self {
        case .badResponse(let status): return "GitHub answered with HTTP status \(status)."
        case .unreadableRelease:       return "GitHub's release information could not be read."
        }
    }
}

/// Asks GitHub for the latest published release. Only `api.github.com` is
/// contacted, and only the release's tag and page URL are read.
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

        struct Release: Decodable {
            let tag_name: String
            let html_url: URL
        }
        guard let release = try? JSONDecoder().decode(Release.self, from: data),
              let latest = AppVersion(release.tag_name)
        else { throw UpdateCheckError.unreadableRelease }

        return latest > currentVersion
            ? .available(AppRelease(version: latest, pageURL: release.html_url))
            : .upToDate(latest: latest)
    }

    /// True when AutoHush was installed with the Homebrew cask.
    static var isHomebrewInstall: Bool {
        ["/opt/homebrew/Caskroom/autohush", "/usr/local/Caskroom/autohush"]
            .contains { FileManager.default.fileExists(atPath: $0) }
    }
}
