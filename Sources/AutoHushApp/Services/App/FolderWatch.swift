import Foundation

/// Calls back whenever an item in a folder is added, removed or renamed: an
/// app installed, moved to the Trash, deleted or swapped by an update. macOS
/// doesn't announce these. It waits for the file system to report a change,
/// with no polling, and stops when released.
@MainActor
final class FolderWatch: FolderWatching {
    private let source: any DispatchSourceFileSystemObject
    /// The folder itself was deleted or renamed: the watch follows the old
    /// one, so it's to be opened again on the path (K2-3 of 11-11).
    private(set) var isGone = false

    /// `nil` when the folder can't be opened, e.g. it doesn't exist.
    init?(folder: URL, onChange: @escaping @MainActor () -> Void) {
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: .main
        )
        source.setEventHandler { [weak self, source] in
            MainActor.assumeIsolated {
                if !source.data.isDisjoint(with: [.delete, .rename]) { self?.isGone = true }
                onChange()
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}

/// A folder's watch that can tell its folder went away (`FolderWatch`).
@MainActor
protocol FolderWatching: AnyObject {
    var isGone: Bool { get }
}

extension FolderWatch {
    /// Starts watching a folder, calling back on each change; the watch lasts
    /// as long as what it returns is kept.
    typealias Start = @MainActor (URL, @escaping @MainActor () -> Void) -> AnyObject?

    static let start: Start = { FolderWatch(folder: $0, onChange: $1) }
}
