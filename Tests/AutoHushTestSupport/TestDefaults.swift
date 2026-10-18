import Foundation

/// A UserDefaults suite of a test's own, named by a path in a temporary
/// folder of its own, so its file is kept there, not in
/// ~/Library/Preferences. `remove()` removes the domain and the folder. A
/// suite's file removed from ~/Library/Preferences comes back: the
/// preferences daemon writes it again, empty, seconds later (measured,
/// 2026-10-18). In a folder that's gone, it can't.
package struct TestDefaults: Sendable {
    private let folder: URL
    private let name: String

    /// A new suite, in a folder named `prefix` and a UUID.
    package init(_ prefix: String) {
        folder = FileManager.default.temporaryDirectory.appending(path: "\(prefix)-\(UUID().uuidString)")
        name = folder.appending(path: "defaults").path
    }

    /// The suite's name, a path: its file is this, with ".plist". The folder
    /// is made as it's first asked for, so a suite never used leaves nothing.
    package var suiteName: String {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return name
    }

    package var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }

    package func remove() {
        UserDefaults().removePersistentDomain(forName: name)
        try? FileManager.default.removeItem(at: folder)
    }
}
