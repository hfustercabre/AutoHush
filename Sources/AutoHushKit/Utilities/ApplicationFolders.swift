import Foundation

/// Where apps are installed: what the player list, Add an App… and the web
/// app finder look through, and the folders AutoHush watches for a player
/// installed or removed.
package enum ApplicationFolders {
    /// /Applications, the current user's Applications folder and
    /// /System/Applications. macOS also lists copies elsewhere, such as one
    /// in the Trash or on the disk image it came from.
    package static let all: [URL] = [
        URL(filePath: "/Applications", directoryHint: .isDirectory),
        user,
        URL(filePath: "/System/Applications", directoryHint: .isDirectory),
    ]

    /// Where Safari's web apps are: the current user's Applications folder,
    /// where Safari puts them, then /Applications.
    package static let forWebApps: [URL] = [user, URL(filePath: "/Applications", directoryHint: .isDirectory)]

    private static let user = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory)
}
