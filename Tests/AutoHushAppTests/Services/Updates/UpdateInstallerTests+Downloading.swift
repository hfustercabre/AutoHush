import CryptoKit
import Foundation
import Security
import Testing
@testable import AutoHushApp
import AutoHushTestSupport

extension UpdateInstallerTests {
    // MARK: - Downloading to keep

    @Test("a download is kept where asked, checked against GitHub's checksum")
    func downloadsToFile() async throws {
        let scratch = try Scratch()
        let file = scratch.folder.appending(path: "AutoHush-1.2.0.dmg")
        let digest = try await installer(scratch).download(release(), to: file, allowsConstrainedNetwork: true)
        #expect(digest == UpdateStandIn.sha256)
        #expect(UpdateInstaller.sha256(of: file) == UpdateStandIn.sha256)
    }

    @Test("a download that doesn't match GitHub's checksum is deleted")
    func deletesWrongDownload() async throws {
        let scratch = try Scratch()
        let file = scratch.folder.appending(path: "AutoHush-1.2.0.dmg")
        await #expect(throws: UpdateInstallError.damaged) {
            try await installer(scratch).download(release(sha256: String(repeating: "0", count: 64)), to: file,
                                                  allowsConstrainedNetwork: true)
        }
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("automatic downloads wait out Low Data Mode; ones the user asks for don't", arguments: [false, true])
    func lowDataMode(allowed: Bool) async throws {
        let scratch = try Scratch()
        let requests = Locked<[URLRequest]>([]) // the download requests made
        _ = try await installer(scratch, requests: requests)
            .download(release(), to: scratch.folder.appending(path: "AutoHush.dmg"), allowsConstrainedNetwork: allowed)
        #expect(requests.value.map(\.allowsConstrainedNetworkAccess) == [allowed])
    }

    /// The fixture's update prepared from a copy of its disk image kept in
    /// the scratch folder, marked as a browser marks a download.
    private func preparedFromKeptImage() async throws
        -> (fixture: UpdateFixture, scratch: Scratch, kept: URL, requests: Locked<[URLRequest]>, sut: UpdateInstaller, update: PreparedUpdate) {
        let fixture = try UpdateFixture.shared.get()
        let scratch = try Scratch()
        let kept = scratch.folder.appending(path: "AutoHush-1.2.0.dmg")
        try FileManager.default.copyItem(at: fixture.diskImage, to: kept)
        let mark = "0083;00000000;Safari;" // downloaded, as a browser marks it
        #expect(setxattr(kept.path, "com.apple.quarantine", mark, mark.utf8.count, 0, XATTR_NOFOLLOW) == 0)
        let requests = Locked<[URLRequest]>([]) // the download requests made
        let sut = installer(scratch, requirement: fixture.requirement, requests: requests)
        let update = try await sut.prepare(release(sha256: fixture.sha256), image: KeptImage(file: kept, sha256: fixture.sha256),
                                           allowsConstrainedNetwork: true)
        return (fixture, scratch, kept, requests, sut, update)
    }

    @Test("an update is prepared from a kept image without downloading, and the image stays", .slow)
    func preparesFromKeptImage() async throws {
        let bench = try await preparedFromKeptImage()
        defer { bench.sut.discard(bench.update) }
        #expect(UpdateInstaller.isSigned(bench.update.app, satisfying: bench.fixture.requirement))
        #expect(bench.requests.value.isEmpty)
        #expect(FileManager.default.fileExists(atPath: bench.kept.path))
        #expect(!bench.scratch.mounts.noted.isEmpty && bench.scratch.mounts.stillMounted.isEmpty)
    }

    @Test("an update prepared from a kept image isn't marked as downloaded", .slow)
    func keptImageCopyNotMarked() async throws {
        let bench = try await preparedFromKeptImage()
        defer { bench.sut.discard(bench.update) }
        let files = FileManager.default.enumerator(at: bench.update.app, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        for url in [bench.update.app] + files {
            #expect(getxattr(url.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) == -1, "\(url.lastPathComponent)")
        }
    }

    @Test("an update prepared from a kept image, changed after signing, fails the signature check", .slow)
    func keptImageCopyChanged() async throws {
        let bench = try await preparedFromKeptImage()
        defer { bench.sut.discard(bench.update) }
        // Its Info.plist, which the signature covers, changed: no longer what was signed.
        let info = bench.update.app.appending(path: "Contents/Info.plist")
        let changed = try #require(NSMutableDictionary(contentsOf: info))
        changed["CFBundleShortVersionString"] = "9.9.9"
        try changed.write(to: info)
        #expect(!UpdateInstaller.isSigned(bench.update.app, satisfying: bench.fixture.requirement))
    }

    @Test("a kept image that changed since it was downloaded is refused")
    func refusesChangedKeptImage() async throws {
        let scratch = try Scratch()
        let kept = scratch.folder.appending(path: "AutoHush-1.2.0.dmg")
        try Data("not the download".utf8).write(to: kept)
        await #expect(throws: UpdateInstallError.damaged) {
            try await installer(scratch).prepare(release(), image: KeptImage(file: kept, sha256: UpdateStandIn.sha256),
                                         allowsConstrainedNetwork: true)
        }
    }
}
