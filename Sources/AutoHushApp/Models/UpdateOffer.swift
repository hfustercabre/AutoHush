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
}

extension UpdateOffer {
    /// While a check runs: Settings' update status, and the menu's Updates
    /// button.
    static var checkingTitle: String {
        String(localized: "Checking…", comment: "While an update check runs: the update status in Settings, and the menu's Updates button (keep it short there)")
    }
}
