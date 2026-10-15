/// Why an app picked from the disk (Other App…) can't be checked.
enum OtherAppProblem: Error, Equatable {
    /// Not an app bundle with a bundle ID.
    case notAnApp
    /// AutoHush supports it already: it's chosen from the players.
    case supported(String)
    /// AutoHush itself.
    case autoHush
}
