import Foundation
import AutoHushKit

/// Each update choice as Settings and Diagnostics show it.
extension AutomaticUpdates {
    var title: String {
        switch self {
        case .notify:
            return String(localized: "Notify me", comment: "Settings: an update choice")
        case .download:
            return String(localized: "Download it and notify me", comment: "Settings: an update choice")
        case .install:
            return String(localized: "Install it automatically", comment: "Settings: an update choice")
        }
    }

    /// What the choice means, under the choices.
    var explanation: String {
        switch self {
        case .notify:
            return String(localized: "AutoHush lets you know. Install the update from its menu whenever you like.",
                          comment: "Settings, under the update choice Notify me")
        case .download:
            return String(localized: "AutoHush downloads it and lets you know. It keeps the download for 7 days.",
                          comment: "Settings, under the update choice Download it and notify me")
        case .install:
            return String(localized: "AutoHush installs it when it isn’t holding your player paused, and lets you know afterwards.",
                          comment: "Settings, under the update choice Install it automatically")
        }
    }
}
