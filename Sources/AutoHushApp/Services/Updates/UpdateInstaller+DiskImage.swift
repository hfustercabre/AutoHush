import Foundation
import AutoHushKit

// UpdateInstaller: the disk image, opened out of sight to copy the app out of it.
extension UpdateInstaller {
    /// Opens the disk image read-only and out of sight in Finder, and copies
    /// AutoHush.app out of it.
    func copyApp(outOf imageFile: URL, into folder: URL) async throws -> URL {
        let mountPoint = folder.appending(path: "Volume", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: false)
        let opener = try await attach(imageFile, at: mountPoint)

        let copied = Result {
            let source = mountPoint.appending(path: "AutoHush.app", directoryHint: .isDirectory)
            let kind = try? source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard kind?.isDirectory == true, kind?.isSymbolicLink == false else { throw UpdateInstallError.damaged }
            let app = folder.appending(path: "AutoHush.app", directoryHint: .isDirectory)
            try FileManager.default.copyItem(at: source, to: app)
            return app
        }
        await detach(mountPoint, openedWith: opener)
        return try copied.get()
    }

    /// Opens the disk image at `mountPoint` with the first tool that manages
    /// to, and returns that tool's place in `diskImageTools`, to close it
    /// again. A tool this macOS lacks fails, as does one that takes too
    /// long, and the next one is tried.
    private func attach(_ imageFile: URL, at mountPoint: URL) async throws -> Int {
        for (index, tool) in diskImageTools.enumerated() {
            if await run(tool.path, tool.attachArguments(imageFile.path, Self.resolvedPath(mountPoint))) { return index }
            // One stopped at its timeout may have mounted it all the same:
            // closed before the next tool tries the same place.
            if Self.isMounted(at: Self.resolvedPath(mountPoint)) { await detach(mountPoint, openedWith: index) }
        }
        throw UpdateInstallError.damaged
    }

    /// Closes the disk image opened at `mountPoint` with the tool at
    /// `opener`, then, while it's still mounted, with the others in turn, so
    /// that no image stays attached (14.4's diskutil, for one, didn't know
    /// `eject force`).
    func detach(_ mountPoint: URL, openedWith opener: Int) async {
        let path = Self.resolvedPath(mountPoint)
        let tool = diskImageTools[opener]
        await run(tool.path, tool.detachArguments(path))
        for other in diskImageTools[(opener + 1)...] + diskImageTools[..<opener] where Self.isMounted(at: path) {
            await run(other.path, other.detachArguments(path))
        }
    }

    /// `url`'s path with symbolic links resolved, the way macOS records where
    /// a volume is mounted (/var/folders/… is /private/var/folders/…).
    /// `diskutil eject` finds a volume only by that path.
    static func resolvedPath(_ url: URL) -> String {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path, let resolved = realpath(path, nil) else { return url.path }
            defer { free(resolved) }
            return String(cString: resolved)
        }
    }

    /// Whether a volume is mounted at `path` (resolved, as macOS records it).
    static func isMounted(at path: String) -> Bool {
        var volume = statfs()
        guard statfs(path, &volume) == 0 else { return false }
        return withUnsafeBytes(of: volume.f_mntonname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) } == path
    }

    /// Runs a disk image tool, for `diskImageTimeout` at most: whether it
    /// did what it was asked (exited with 0).
    @discardableResult
    private func run(_ tool: String, _ arguments: [String]) async -> Bool {
        await ToolRun(URL(filePath: tool), arguments, timeout: diskImageTimeout).run().succeeded
    }
}
