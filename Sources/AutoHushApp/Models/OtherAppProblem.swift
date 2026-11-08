/// Why an app picked from the disk (Other App…) can't be checked.
enum OtherAppProblem: Error, Equatable {
    /// Not an app bundle with a bundle ID.
    case notAnApp
    /// Nothing there: an app moved or deleted since it was added (F-7's
    /// note, N1, the user's pick of 2026-11-08).
    case notFound
    /// AutoHush supports it already: it's chosen from the players.
    case supported(String)
    /// AutoHush itself.
    case autoHush
}
