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
