import Foundation

/// An update the menu offers, and how far along it is.
struct UpdateOffer: Equatable {
    enum State: Equatable {
        /// Found; installing it downloads it first.
        case available
        /// Downloaded and kept; installing it is quick.
        case downloaded
        /// Being downloaded and installed right now.
        case installing
    }

    let release: AppRelease
    let state: State
    /// This copy can install it itself; else its alert only tells where to
    /// get it (the release page, Homebrew).
    var canInstall = true
}

extension UpdateOffer {
    /// AutoHush's updates: the menu's button, the heading over them in
    /// Settings → About, and a Diagnostics row.
    static var updatesTitle: String {
        String(localized: "Updates", comment: "Menu toolbar button, Settings → About's heading over the update settings, and a Diagnostics row: AutoHush's updates")
    }

    /// While a check runs: Settings' update status, and the menu's Updates
    /// button.
    static var checkingTitle: String {
        String(localized: "Checking…", comment: "While an update check runs: the update status in Settings, and the menu's Updates button (keep it short there)")
    }
}
