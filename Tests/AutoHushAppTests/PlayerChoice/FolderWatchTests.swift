import Foundation
import Testing
@testable import AutoHushApp

@Suite("FolderWatch")
@MainActor
struct FolderWatchTests {
    /// Counts the changes reported for a temporary folder of its own.
    @MainActor
    private final class Scratch {
        let folder = FileManager.default.temporaryDirectory.appending(path: "FolderWatchTests-\(UUID().uuidString)")
        let elsewhere = FileManager.default.temporaryDirectory.appending(path: "FolderWatchTests-\(UUID().uuidString)")
        var changes = 0

        init() throws {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: elsewhere)
        }

        /// Waits until a change beyond `count` is reported, or a second passes.
        func waitForChange(after count: Int) async {
            for _ in 0..<100 where changes == count { try? await Task.sleep(for: .milliseconds(10)) }
        }
    }

    @Test("installing an app, moving it away as the Trash does, and deleting it are each reported")
    func reportsChanges() async throws {
        let scratch = try Scratch()
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
        let scratch = try Scratch()
        var watch = FolderWatch(folder: scratch.folder) { scratch.changes += 1 }
        #expect(watch != nil)
        watch = nil

        try FileManager.default.createDirectory(at: scratch.folder.appending(path: "Player.app"), withIntermediateDirectories: false)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(scratch.changes == 0)
    }

    @Test("a folder that doesn't exist can't be watched")
    func missingFolder() {
        let missing = FileManager.default.temporaryDirectory.appending(path: "FolderWatchTests-missing-\(UUID().uuidString)")
        #expect(FolderWatch(folder: missing) {} == nil)
    }
}
