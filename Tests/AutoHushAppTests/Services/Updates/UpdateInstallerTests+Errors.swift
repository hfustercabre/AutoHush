import CryptoKit
import Foundation
import Security
import Testing
@testable import AutoHushApp
import AutoHushTestSupport

extension UpdateInstallerTests {
    // MARK: - Where it can install

    @Test("a copy not signed with a certificate, or that can't write to its folder, can't update itself")
    func unavailability() throws {
        let scratch = try Scratch()
        #expect(installer(scratch).unavailability == nil)
        #expect(installer(scratch, requirement: nil).unavailability == .notSignedWithCertificate)

        let applications = scratch.installedApp.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: applications.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: applications.path) }
        #expect(installer(scratch).unavailability == .readOnlyLocation)
    }

    // MARK: - What went wrong

    @Test("each error says what went wrong in the user's words, and in English for the log, a failed swap's reason too",
          arguments: [
            (UpdateInstallError.unavailable(.notSignedWithCertificate),
             "This copy of AutoHush can’t update itself, because it isn’t signed with AutoHush’s certificate.",
             "This copy isn't signed with AutoHush's certificate, so it can't update itself."),
            (.unavailable(.readOnlyLocation),
             "AutoHush can’t update itself, because it can’t write to the folder it’s in.",
             "AutoHush can't write to the folder it's in, so it can't update itself."),
            (.noDiskImage, "This release has no disk image to install from.", "The release has no disk image to install from."),
            (.badResponse(404), "GitHub answered with HTTP status 404.", "GitHub answered with HTTP status 404."),
            (.damaged, "The download is damaged.", "The download is damaged."),
            (.notGenuine, "The download isn’t signed by AutoHush’s developer, so it wasn’t installed.",
             "The download isn't signed by AutoHush's developer."),
            (.wrongVersion, "The download doesn’t contain the version GitHub announced.",
             "The download doesn't contain the version GitHub announced."),
            (.notReplaced("Le disque est plein.", logReason: "The disk is full."),
             "AutoHush couldn’t replace itself: Le disque est plein.", "AutoHush couldn't replace itself: The disk is full."),
            (.needsNewerMacOS("15.0"), "This version needs macOS 15.0 or later, so it wasn’t installed.",
             "The download needs macOS 15.0 or later."),
          ])
    func errorTexts(error: UpdateInstallError, shown: String, logged: String) {
        #expect(error.errorDescription == shown)
        #expect(error.logDescription == logged)
    }

    @Test("an update is installed only on the macOS it needs or later; a minimum it can't read doesn't hold it back",
          arguments: [("14.4", (14, 4, 1), true), ("14.4", (14, 3, 9), false), ("15", (15, 0, 0), true),
                      ("15.0.1", (15, 0, 0), false), ("26.1", (27, 0, 0), true), ("soon", (14, 4, 0), true)])
    func neededMacOS(minimum: String, system: (Int, Int, Int), installs: Bool) {
        let version = OperatingSystemVersion(majorVersion: system.0, minorVersion: system.1, patchVersion: system.2)
        #expect(UpdateInstaller.isAtLeast(minimum, version) == installs)
    }
}
