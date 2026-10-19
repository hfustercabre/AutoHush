import Foundation

/// The check's kept page buttons, by bundle ID, in a JSON file of its caches
/// (`--caches`: AutoHush's own caches folder when it runs the check).
package struct SavedButtonStore: Sendable {
    let file: URL

    package init(file: URL) {
        self.file = file
    }

    /// Every app's; from a file written before recipes, the paths alone.
    package func all() -> [String: SavedButton] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        if let all = try? JSONDecoder().decode([String: SavedButton].self, from: data) { return all }
        return ((try? JSONDecoder().decode([String: ButtonPath].self, from: data)) ?? [:]).mapValues { SavedButton(path: $0) }
    }

    /// Changes `bundleID`'s and writes the file again, whole or not at all:
    /// a run stopped mid-write (`_exit`) would leave a cut file, read as
    /// empty, and the next save would keep only this app.
    package func change(_ bundleID: String, _ change: (inout SavedButton) -> Void) {
        var all = all()
        var mine = all[bundleID] ?? SavedButton()
        change(&mine)
        all[bundleID] = mine
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(all).write(to: file, options: .atomic)
    }
}
