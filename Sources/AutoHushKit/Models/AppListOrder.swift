import Foundation

/// How Settings → Apps orders its apps.
package struct AppListOrder: Equatable, Sendable {
    package enum Criterion: String, CaseIterable, Sendable {
        /// The app that played most recently first.
        case lastPlayed
        /// By name, A to Z.
        case name
        /// Apps that pause the music first, then the ignored ones, each by name.
        case state
    }

    package var criterion: Criterion
    /// The other way round: the oldest first, Z to A, or the ignored apps first.
    package var isReversed: Bool

    /// The most recent first.
    package static let standard = AppListOrder(criterion: .lastPlayed)

    package init(criterion: Criterion, isReversed: Bool = false) {
        self.criterion = criterion
        self.isReversed = isReversed
    }
}
