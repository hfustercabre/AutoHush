import AppKit
import OSLog
import UserNotifications

/// Something about updates worth a notification.
enum UpdateNotice: Equatable, Sendable {
    /// A newer version is available ("Notify me").
    case available(AppVersion, running: AppVersion)
    /// A newer version is downloaded and ready ("Download it and notify me").
    case downloaded(AppVersion)
    /// AutoHush was updated to this version.
    case installed(AppVersion)
    /// Installing this version automatically failed.
    case installFailed(AppVersion)

    enum Kind: String, Sendable {
        case available, downloaded, installed, installFailed
    }

    var kind: Kind {
        switch self {
        case .available: .available
        case .downloaded: .downloaded
        case .installed: .installed
        case .installFailed: .installFailed
        }
    }

    var version: AppVersion {
        switch self {
        case .available(let version, _), .downloaded(let version), .installed(let version), .installFailed(let version):
            version
        }
    }

    /// E.g. "available 0.3.8": each notice is sent once.
    var key: String { "\(kind.rawValue) \(version)" }

    var title: String {
        let version = version.description
        switch self {
        case .available:
            return String(localized: "AutoHush \(version) is available",
                          comment: "Notification title; %@ is the new version")
        case .downloaded:
            return String(localized: "AutoHush \(version) is ready to install",
                          comment: "Notification title; %@ is the new version, already downloaded")
        case .installed:
            return String(localized: "AutoHush was updated to \(version)",
                          comment: "Notification title after an update; %@ is the version now running")
        case .installFailed:
            return String(localized: "Couldn’t update AutoHush to \(version)",
                          comment: "Notification title; %@ is the version that failed to install")
        }
    }

    var body: String {
        switch self {
        case .available(_, let running):
            return String(localized: "You’re running \(running.description). Click to see what’s new and install it.",
                          comment: "Notification text; %@ is the installed version")
        case .downloaded:
            return String(localized: "It’s downloaded. Click to see what’s new and install it.",
                          comment: "Notification text for a downloaded update")
        case .installed:
            return String(localized: "Click to see what’s new.", comment: "Notification text after an update")
        case .installFailed:
            return String(localized: "Click to try again, or to download it yourself.",
                          comment: "Notification text after an update failed to install")
        }
    }
}

/// What the user decided about AutoHush's notifications.
enum NotificationPermission: Equatable, Sendable {
    /// Not asked yet, or asked with no answer yet. Reset Notifications… in
    /// System Settings brings AutoHush back here, so it can ask again.
    case notAsked
    case allowed
    /// The user turned notifications off.
    case off
}
