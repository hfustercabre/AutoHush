import Foundation
import Testing
@testable import AutoHushApp
import AutoHushTestSupport

@Suite("FolderWatch")
@MainActor
struct FolderWatchTests {
    /// Counts the changes reported for a temporary folder of its own.
    @MainActor
    private final class Scratch {
        private let watched = TemporaryFolder("FolderWatchTests"), other = TemporaryFolder("FolderWatchTests")
        var folder: URL { watched.url }
        var elsewhere: URL { other.url }
        var changes = 0

        /// Waits until a change beyond `count` is reported.
        func waitForChange(after count: Int, sourceLocation: SourceLocation = #_sourceLocation) async {
            await TestWait.until(sourceLocation: sourceLocation) { changes != count }
        }
    }

    @Test("installing an app, moving it away as the Trash does, and deleting it are each reported")
    func reportsChanges() async throws {
        let scratch = Scratch()
        let watch = FolderWatch(folder: scratch.folder) { scratch.changes += 1 }
        #expect(watch != nil)
        let app = scratch.folder.appending(path: "Player.app")

        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: false)
        await scratch.waitForChange(after: 0)
        #expect(scratch.changes > 0)

        var count = scratch.changes
        let moved = scratch.elsewhere.appending(path: "Player.app")
        try FileManager.default.moveItem(at: app, to: moved)
        await scratch.waitForChange(after: count)
        #expect(scratch.changes > count)

        try FileManager.default.moveItem(at: moved, to: app)
        await scratch.waitForChange(after: scratch.changes)
        count = scratch.changes
        try FileManager.default.removeItem(at: app)
        await scratch.waitForChange(after: count)
        #expect(scratch.changes > count)
        withExtendedLifetime(watch) {}
    }

    @Test("a released watch reports nothing")
    func stopsWhenReleased() async throws {
        let scratch = Scratch()
        var watch = FolderWatch(folder: scratch.folder) { scratch.changes += 1 }
        #expect(watch != nil)
        watch = nil
        // Another watch of the folder, kept: once it hears of the change, the
        // released one would have too.
        let heard = Locked(0)
        let kept = FolderWatch(folder: scratch.folder) { heard.increment() }

        try FileManager.default.createDirectory(at: scratch.folder.appending(path: "Player.app"), withIntermediateDirectories: false)
        await TestWait.until { heard.value > 0 }
        #expect(scratch.changes == 0)
        withExtendedLifetime(kept) {}
    }

    @Test("a folder that doesn't exist can't be watched")
    func missingFolder() {
        let missing = FileManager.default.temporaryDirectory.appending(path: "FolderWatchTests-missing-\(UUID().uuidString)")
        #expect(FolderWatch(folder: missing) {} == nil)
        #expect(FolderWatch.start(missing, {}) == nil) // the app's way of starting one
    }
}
