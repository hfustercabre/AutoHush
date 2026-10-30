import CryptoKit
import Foundation
import Security
import Testing
@testable import AutoHushApp
import AutoHushTestSupport

extension UpdateInstallerTests {
    // MARK: - Installing

    @Test("installing swaps the update in and has it opened once AutoHush quits")
    func installs() throws {
        let scratch = try Scratch()
        let update = try Self.preparedUpdate(next: scratch.installedApp)
        let log = RelaunchLog()

        try installer(scratch, relaunchLog: log).install(update)

        #expect(try String(contentsOf: scratch.installedApp.appending(path: "version.txt"), encoding: .utf8) == "new")
        #expect(!FileManager.default.fileExists(atPath: update.folder.path))
        #expect(log.opened == [scratch.installedApp])
        #expect(log.cancelled == 0)
    }

    @Test("a failed swap leaves the installed app alone, calls the relaunch off, and moves the copy prepared to the Trash, its folder gone")
    func failedSwap() throws {
        let scratch = try Scratch()
        let update = try Self.preparedUpdate(next: scratch.installedApp)
        // The installed app's folder can't be changed: it can't be swapped.
        let applications = scratch.installedApp.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: applications.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: applications.path) }
        let log = RelaunchLog()

        #expect {
            try installer(scratch, relaunchLog: log).install(update)
        } throws: { error in
            guard case .notReplaced = error as? UpdateInstallError else { return false }
            return true
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: applications.path)
        #expect(try String(contentsOf: scratch.installedApp.appending(path: "version.txt"), encoding: .utf8) == "old")
        #expect(log.cancelled == 1)
        #expect(scratch.trashed.value == [update.app])
        #expect(!FileManager.default.fileExists(atPath: update.folder.path))
    }

    @Test("the quarantine mark is removed from the app and everything in it")
    func removesQuarantine() throws {
        let scratch = try Scratch()
        let app = scratch.installedApp
        let file = app.appending(path: "version.txt")
        let mark = "0083;00000000;Safari;"
        for url in [app, file] {
            #expect(setxattr(url.path, "com.apple.quarantine", mark, mark.utf8.count, 0, XATTR_NOFOLLOW) == 0)
        }

        UpdateInstaller.removeQuarantine(from: app)

        for url in [app, file] {
            #expect(getxattr(url.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) == -1)
        }
    }

    /// A prepared "new" app, in a folder on the same volume as `installed`.
    private static func preparedUpdate(next installed: URL) throws -> PreparedUpdate {
        let folder = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: installed, create: true
        )
        let app = folder.appending(path: "AutoHush.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: false)
        try Data("new".utf8).write(to: app.appending(path: "version.txt"))
        return PreparedUpdate(version: AppVersion("1.2.0")!, app: app, folder: folder)
    }
}
