import Foundation

/// Calls back whenever an item in a folder is added, removed or renamed: an
/// app installed, moved to the Trash, deleted or swapped by an update. macOS
/// doesn't announce these. It waits for the file system to report a change,
/// with no polling, and stops when released.
@MainActor
final class FolderWatch {
    private let source: any DispatchSourceFileSystemObject

    /// `nil` when the folder can't be opened, e.g. it doesn't exist.
    init?(folder: URL, onChange: @escaping @MainActor () -> Void) {
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: .main
        )
        source.setEventHandler { MainActor.assumeIsolated { onChange() } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}

extension FolderWatch {
    /// Starts watching a folder, calling back on each change; the watch lasts
    /// as long as what it returns is kept.
    typealias Start = @MainActor (URL, @escaping @MainActor () -> Void) -> AnyObject?

    static let start: Start = { FolderWatch(folder: $0, onChange: $1) }
}
