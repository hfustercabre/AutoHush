import CryptoKit
import Foundation
import Security
import Testing
@testable import AutoHushApp
import AutoHushTestSupport

extension UpdateInstallerTests {
    // MARK: - Preparing

    @Test("diskutil opens and closes the disk image, as from macOS 27", .slow, .enabled(if: isMacOS27OrLater))
    func opensWithDiskutil() async throws {
        try await expectPrepared(openingWith: [.diskutil])
    }

    @Test("hdiutil opens and closes the disk image, as before macOS 27", .slow)
    func opensWithHdiutil() async throws {
        try await expectPrepared(openingWith: [.hdiutil])
    }

    @Test("diskutil is tried first from macOS 27, hdiutil alone before")
    func diskImageToolOrder() {
        // From macOS 27, which deprecates hdiutil's attach and detach. On 14.4, `diskutil image`
        // opened images whose files this process couldn't read, and its eject didn't know `force`.
        let order = isMacOS27OrLater ? ["/usr/sbin/diskutil", "/usr/bin/hdiutil"] : ["/usr/bin/hdiutil"]
        #expect(DiskImageTool.inOrderOfPreference.map(\.path) == order)
    }

    @Test("a disk image tool that's missing or fails makes way for the next one, also one that can't close the image", .slow)
    func fallsBackToNextTool() async throws {
        let missing = DiskImageTool(path: "/nonexistent/diskutil", attachArguments: { _, _ in [] }, detachArguments: { _ in [] })
        let failing = DiskImageTool(path: "/usr/bin/false", attachArguments: { _, _ in [] }, detachArguments: { _ in [] })
        // Opens it, then fails to close it, as 14.4's diskutil did.
        let leaving = DiskImageTool(path: "/usr/bin/hdiutil", attachArguments: DiskImageTool.hdiutil.attachArguments,
                                    detachArguments: { _ in ["detach", "/nonexistent"] })
        try await expectPrepared(openingWith: [missing, failing, leaving, .hdiutil])
    }

    /// Prepares the fixture's update, opening its disk image with `tools`,
    /// and checks the result.
    private func expectPrepared(openingWith tools: [DiskImageTool]) async throws {
        let fixture = try UpdateFixture.shared.get()
        let scratch = try Scratch()
        let update = try await installer(scratch, requirement: fixture.requirement, serving: fixture.diskImage, diskImageTools: tools)
            .prepare(release(sha256: fixture.sha256), image: nil, allowsConstrainedNetwork: true)

        #expect(update.version == AppVersion(UpdateFixture.version))
        let info = NSDictionary(contentsOf: update.app.appending(path: "Contents/Info.plist"))
        #expect(info?["CFBundleShortVersionString"] as? String == UpdateFixture.version)
        #expect(UpdateInstaller.isSigned(update.app, satisfying: fixture.requirement))
        // Only the app is left: the download is deleted and the image detached.
        let contents = try FileManager.default.contentsOfDirectory(atPath: update.folder.path)
        #expect(contents.sorted() == ["AutoHush.app", "Volume"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: update.folder.appending(path: "Volume").path).isEmpty)
        #expect(!scratch.mounts.noted.isEmpty && scratch.mounts.stillMounted.isEmpty)

        installer(scratch).discard(update)
        #expect(!FileManager.default.fileExists(atPath: update.folder.path))
    }

    @Test("an app signed by anyone else is refused, and nothing is left behind", .slow)
    func refusesOtherSigners() async throws {
        let fixture = try UpdateFixture.shared.get()
        let scratch = try Scratch()
        let autoHush = #"identifier "com.autohush.AutoHush" and certificate leaf = H"085edf2752c4f31bcdff25dbe14636958d50cdf6""#
        await #expect(throws: UpdateInstallError.notGenuine) {
            try await installer(scratch, requirement: autoHush, serving: fixture.diskImage)
                .prepare(release(sha256: fixture.sha256), image: nil, allowsConstrainedNetwork: true)
        }
        #expect(!scratch.mounts.noted.isEmpty && scratch.mounts.stillMounted.isEmpty)
        #expect(scratch.mounts.stagingIsGone)
    }

    /// Prepares an update with a disk image tool that hangs, ignoring the
    /// request to stop as one stuck in the kernel would, given 0.3 s:
    /// refused as damaged. Returns how long it took.
    private func preparedWithHungTool(_ scratch: Scratch) async -> TimeInterval {
        let hung = DiskImageTool(path: "/bin/sh", attachArguments: { _, _ in ["-c", "trap '' TERM; sleep 5"] },
                                 detachArguments: { _ in [] })
        let started = Date()
        await #expect(throws: UpdateInstallError.damaged) {
            try await installer(scratch, diskImageTools: [hung], diskImageTimeout: 0.3)
                .prepare(release(), image: nil, allowsConstrainedNetwork: true)
        }
        return Date().timeIntervalSince(started)
    }

    @Test("a disk image tool that hangs is stopped once its time is up, and the download refused as damaged: an install never waits for good")
    func hungToolTimesOut() async throws {
        let scratch = try Scratch()
        #expect(await preparedWithHungTool(scratch) < 4) // not waited for
    }

    @Test("a disk image tool that hangs, once stopped, leaves no staging folder")
    func hungToolLeavesNothing() async throws {
        let scratch = try Scratch()
        _ = await preparedWithHungTool(scratch)
        #expect(scratch.mounts.stagingIsGone)
    }

    @Test("a disk image tool has two minutes to open or close an image")
    func diskImageToolTimeout() {
        #expect(UpdateInstaller.diskImageToolTimeout == 120)
    }

    @Test("a download that doesn't match GitHub's checksum is refused")
    func refusesWrongChecksum() async throws {
        let scratch = try Scratch()
        await #expect(throws: UpdateInstallError.damaged) {
            try await installer(scratch).prepare(release(sha256: String(repeating: "0", count: 64)), image: nil, allowsConstrainedNetwork: true)
        }
    }

    @Test("a download that isn't a disk image is refused, and its staging folder goes", .slow)
    func refusesNonImage() async throws {
        let scratch = try Scratch()
        let page = scratch.folder.appending(path: "page.html")
        try Data("<html>Not Found</html>".utf8).write(to: page)
        await #expect(throws: UpdateInstallError.damaged) {
            try await installer(scratch, serving: page).prepare(release(sha256: nil), image: nil, allowsConstrainedNetwork: true)
        }
        #expect(scratch.mounts.stagingIsGone)
    }

    @Test("a disk image is refused, leaving nothing behind, when its app isn't the version announced or needs a newer macOS, or AutoHush.app is a link",
          .slow, arguments: [
            (ImagedApp.needing(macOS: "14.4"), "9.9.9", UpdateInstallError.wrongVersion),
            (.needing(macOS: "99.0"), UpdateFixture.version, .needsNewerMacOS("99.0")),
            (.link(to: "/System/Applications/Calculator.app"), UpdateFixture.version, .damaged),
          ])
    func refusesUnfitImage(imaged: ImagedApp, announced: String, refusal: UpdateInstallError) async throws {
        let scratch = try Scratch()
        let fixture = try UpdateFixture.kept(imaged)
        await #expect(throws: refusal) {
            try await installer(scratch, requirement: fixture.requirement, serving: fixture.diskImage)
                .prepare(release(announced, sha256: fixture.sha256), image: nil, allowsConstrainedNetwork: true)
        }
        #expect(!scratch.mounts.noted.isEmpty && scratch.mounts.stillMounted.isEmpty)
        #expect(scratch.mounts.stagingIsGone)
    }

    @Test("a failed download is reported with its HTTP status")
    func refusesHTTPError() async throws {
        let scratch = try Scratch()
        await #expect(throws: UpdateInstallError.badResponse(404)) {
            try await installer(scratch, status: 404).prepare(release(), image: nil, allowsConstrainedNetwork: true)
        }
    }

    @Test("a release without a disk image can't be installed")
    func refusesReleaseWithoutImage() async throws {
        let scratch = try Scratch()
        await #expect(throws: UpdateInstallError.noDiskImage) {
            try await installer(scratch).prepare(release(diskImage: false), image: nil, allowsConstrainedNetwork: true)
        }
    }
}
