import Foundation
import AutoHushKit

/// Why this copy of AutoHush can't install updates by itself.
enum UpdateInstallUnavailability: Equatable, Sendable {
    /// It isn't signed with a certificate (a development build), so there is
    /// no way to tell that an update comes from the same developer.
    case notSignedWithCertificate
    /// It can't replace itself: the app or its folder is read-only for this
    /// user (on the disk image, or in another user's folder).
    case readOnlyLocation

    /// Shown in Settings under the update choices, which it limits to "Notify me".
    var explanation: String {
        switch self {
        case .notSignedWithCertificate:
            return String(localized: "This copy of AutoHush can’t update itself, because it isn’t signed with AutoHush’s certificate.",
                          comment: "Settings, under the update choices (development builds)")
        case .readOnlyLocation:
            return String(localized: "AutoHush can’t update itself, because it can’t write to the folder it’s in.",
                          comment: "Settings, under the update choices")
        }
    }
}

/// Why an update could not be installed.
enum UpdateInstallError: LocalizedError, LoggableError, Equatable {
    case unavailable(UpdateInstallUnavailability)
    /// The release has no disk image to install from.
    case noDiskImage
    case badResponse(Int)
    /// The download doesn't match GitHub's checksum, can't be opened, or
    /// holds no AutoHush.app.
    case damaged
    /// The app in the download isn't signed by the running app's developer
    /// (its bundle ID and team: a renewed certificate is fine).
    case notGenuine
    /// The app in the download isn't the version the release announced.
    case wrongVersion
    /// The app in the download needs a newer macOS than this Mac's (its
    /// `LSMinimumSystemVersion`): installed, it wouldn't open.
    case needsNewerMacOS(String)
    /// Swapping in the new app failed, for the reason given: in the user's
    /// language, and in English for the log.
    case notReplaced(String, logReason: String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return reason.explanation
        case .noDiskImage:
            return String(localized: "This release has no disk image to install from.", comment: "Update install error")
        case .badResponse(let status):
            return String(localized: "GitHub answered with HTTP status \(status).",
                          comment: "Update check error; %lld is an HTTP status code")
        case .damaged:
            return String(localized: "The download is damaged.", comment: "Update install error")
        case .notGenuine:
            return String(localized: "The download isn’t signed by AutoHush’s developer, so it wasn’t installed.",
                          comment: "Update install error")
        case .wrongVersion:
            return String(localized: "The download doesn’t contain the version GitHub announced.", comment: "Update install error")
        case .needsNewerMacOS(let minimum):
            return String(localized: "This version needs macOS \(minimum) or later, so it wasn’t installed.",
                          comment: "Update install error; %@ is a macOS version, e.g. “15.0”")
        case .notReplaced(let reason, _):
            return String(localized: "AutoHush couldn’t replace itself: \(reason)",
                          comment: "Update install error; %@ is the reason macOS gave")
        }
    }

    var logDescription: String {
        switch self {
        case .unavailable(.notSignedWithCertificate): "This copy isn't signed with AutoHush's certificate, so it can't update itself."
        case .unavailable(.readOnlyLocation): "AutoHush can't write to the folder it's in, so it can't update itself."
        case .noDiskImage: "The release has no disk image to install from."
        case .badResponse(let status): "GitHub answered with HTTP status \(status)."
        case .damaged: "The download is damaged."
        case .notGenuine: "The download isn't signed by AutoHush's developer."
        case .wrongVersion: "The download doesn't contain the version GitHub announced."
        case .needsNewerMacOS(let minimum): "The download needs macOS \(minimum) or later."
        case .notReplaced(_, let reason): "AutoHush couldn't replace itself: \(reason)"
        }
    }
}
