import Foundation

/// The menu's parts that open a side window beside it.
enum MenuSidePart: Hashable {
    case players, ignoredApps

    /// The menu's part its row is in.
    var section: MenuSection {
        switch self {
        case .players: .playerRow
        case .ignoredApps: .ignoredApps
        }
    }
}
