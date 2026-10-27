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

    /// What the choice means: the help tag and VoiceOver hint of About's
    /// update pop-up (A4, 2026-10-26).
    var explanation: String {
        switch self {
        case .notify:
            return String(localized: "AutoHush lets you know. Install the update from its menu whenever you like.",
                          comment: "Settings → About: help tag and VoiceOver hint of the update pop-up while Notify me is chosen")
        case .download:
            return String(localized: "AutoHush downloads it and lets you know. It keeps the download for 7 days.",
                          comment: "Settings → About: help tag and VoiceOver hint of the update pop-up while Download it and notify me is chosen")
        case .install:
            return String(localized: "AutoHush installs it when it isn’t holding your player paused, and lets you know afterwards.",
                          comment: "Settings → About: help tag and VoiceOver hint of the update pop-up while Install it automatically is chosen")
        }
    }
}
