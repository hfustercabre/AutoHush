import AppKit
import AutoHushKit

/// A music player as the menu, Settings and the welcome window offer it.
struct PlayerOption: Equatable, Identifiable {
    let bundleID: String
    let name: String
    /// Where the app is installed; `nil` when it isn't, and then it can't be
    /// chosen.
    let appURL: URL?

    var id: String { bundleID }
    var isInstalled: Bool { appURL != nil }

    /// Finds an installed app by bundle ID.
    typealias Locate = @MainActor (String) -> URL?

    static let locateInstalledApp: Locate = {
        firstInstalled(NSWorkspace.shared.urlsForApplications(withBundleIdentifier: $0))
    }

    /// Where apps are installed: /Applications, the current user's
    /// Applications folder and /System/Applications. macOS also lists copies
    /// elsewhere, such as one in the Trash or on the disk image it came from.
    static let applicationFolders: [URL] = [
        URL(filePath: "/Applications", directoryHint: .isDirectory),
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory),
        URL(filePath: "/System/Applications", directoryHint: .isDirectory),
    ]

    /// The first app in one of `folders`, or a folder inside one, that is
    /// still on disk: macOS can list an app deleted moments ago until Launch
    /// Services catches up.
    static func firstInstalled(
        _ urls: [URL],
        in folders: [URL] = applicationFolders,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL? {
        urls.first { url in
            folders.contains { url.path.hasPrefix($0.path + "/") } && exists(url)
        }
    }

    /// Every player in the catalog, in its order, and whether it is installed.
    @MainActor
    static func list(_ catalog: MusicPlayerCatalog, locate: Locate) -> [PlayerOption] {
        catalog.players.map { PlayerOption(bundleID: $0.bundleID, name: $0.name, appURL: locate($0.bundleID)) }
    }

    @MainActor
    func icon(size: CGFloat) -> NSImage {
        AppIcon.image(bundlePath: appURL?.path, size: size)
    }

    /// Under a player that isn't installed, wherever players are offered.
    static var notInstalledLabel: String {
        String(localized: "Not installed", comment: "Under a music player that isn't on this Mac")
    }

    /// Shown in Settings and the welcome window while no supported player is
    /// installed.
    static var noneInstalledWarning: String {
        String(localized: "No supported music player is installed. Install one of these, and choose it here.",
               comment: "Settings and the welcome window, while none of the music players is installed")
    }

    /// In the welcome window when one player is installed and others could
    /// be, e.g. "Spotify is the only supported music player on this Mac.
    /// AutoHush also works with Apple Music and Deezer."; `nil` otherwise.
    static func onlyInstalledNote(among options: [PlayerOption]) -> String? {
        guard let only = options.onlyInstalled else { return nil }
        let others = options.filter { !$0.isInstalled }.map(\.name)
        guard !others.isEmpty else { return nil }
        let list = others.formatted(.list(type: .and))
        return String(localized: "\(only.name) is the only supported music player on this Mac. AutoHush also works with \(list).",
                      comment: "Welcome window; the installed music player, then the other supported ones, e.g. “Apple Music and Deezer”")
    }
}

extension [PlayerOption] {
    /// No supported player is installed: none can be chosen.
    var noneInstalled: Bool { !contains(where: \.isInstalled) }

    /// The one installed player, when exactly one is.
    var onlyInstalled: PlayerOption? {
        let installed = filter(\.isInstalled)
        return installed.count == 1 ? installed[0] : nil
    }
}
