import Foundation

/// A version of AutoHush: a release ("1.2.7"), or one of its release
/// candidates ("1.2.7 RC 1", tagged `v1.2.7-rc.1`), which comes before it.
struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    let components: [Int]
    /// Its number as a release candidate of `components`, or `nil` for the
    /// release itself.
    let releaseCandidate: Int?

    init(components: [Int], releaseCandidate: Int? = nil) {
        self.components = components
        self.releaseCandidate = releaseCandidate
    }

    /// Reads "1.2.7", "v1.2.7", a tag's "1.2.7-rc.1" or the shown "1.2.7 RC 1".
    init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespaces)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        var candidate: Int?
        for marker in ["-rc.", " RC "] {
            guard let range = text.range(of: marker) else { continue }
            guard let number = Int(text[range.upperBound...]), number > 0 else { return nil }
            candidate = number
            text = String(text[..<range.lowerBound])
            break
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        components = parts.compactMap { $0 }
        releaseCandidate = candidate
    }

    /// As people read it: "1.2.7", "1.2.7 RC 1".
    var description: String {
        releaseCandidate.map { "\(number) RC \($0)" } ?? number
    }

    /// As its tag (after the "v") and its disk image name it: "1.2.7",
    /// "1.2.7-rc.1".
    var tagName: String {
        releaseCandidate.map { "\(number)-rc.\($0)" } ?? number
    }

    var isReleaseCandidate: Bool { releaseCandidate != nil }

    private var number: String { components.map(String.init).joined(separator: ".") }

    /// By number; a release candidate comes before its release, and after
    /// the candidates numbered lower.
    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        let left = lhs.components + Array(repeating: 0, count: count - lhs.components.count)
        let right = rhs.components + Array(repeating: 0, count: count - rhs.components.count)
        if left != right { return left.lexicographicallyPrecedes(right) }
        switch (lhs.releaseCandidate, rhs.releaseCandidate) {
        case let (left?, right?): return left < right
        case (.some, nil): return true
        default: return false
        }
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    /// The running app's: its `CFBundleShortVersionString`, and its
    /// `AutoHushReleaseCandidate` when it's a release candidate (`release.sh
    /// --rc` sets it).
    static var current: AppVersion? { AppVersion(info: Bundle.main.infoDictionary ?? [:]) }

    /// A bundle's, as its Info.plist says.
    init?(info: [String: Any]) {
        guard let short = (info["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init), !short.isReleaseCandidate
        else { return nil }
        let candidate = info[Self.releaseCandidateKey] as? Int ?? (info[Self.releaseCandidateKey] as? String).flatMap { Int($0) }
        self.init(components: short.components, releaseCandidate: candidate.flatMap { $0 > 0 ? $0 : nil })
    }

    /// The Info.plist key a release candidate's build carries its number in.
    static let releaseCandidateKey = "AutoHushReleaseCandidate"
}
