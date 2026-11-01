import Foundation

/// What a search found, as VoiceOver hears it once typing pauses
/// (`SearchField`): how many items it shows, or the list's own words for
/// none ("No apps match “…”."), which the list shows then (A14, 2026-11-01).
struct SearchResults: Equatable, Sendable {
    /// How many items the search shows.
    let count: Int
    /// The list's words when it shows none.
    let noMatch: String

    var announcement: String {
        count == 0 ? noMatch : String(localized: "\(count) results",
                                      comment: "VoiceOver, once typing in a search pauses: how many items the search shows (1 or more)")
    }
}
