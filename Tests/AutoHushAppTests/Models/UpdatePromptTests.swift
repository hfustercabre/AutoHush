import Foundation
import Testing
@testable import AutoHushApp

@Suite("UpdatePrompt")
struct UpdatePromptTests {
    private let release = AppRelease.github("0.3.8", diskImage: false)
    private let running = AppVersion("0.3.7")!

    @Test("an update to download says both versions and offers to download and install it")
    func available() {
        let prompt = UpdatePrompt(release: release, running: running, isDownloaded: false, canInstall: true, isHomebrewInstall: false)
        #expect(prompt.title == "AutoHush 0.3.8 Is Available")
        #expect(prompt.message == "You’re running version 0.3.7, and version 0.3.8 is available. Installing it restarts AutoHush.")
        #expect(prompt.buttons.map(\.title) == ["Download and Install", "Later", "Open Release Page"])
        #expect(prompt.buttons.map(\.choice) == [.install, .later, .openReleasePage])
    }

    @Test("a downloaded update says both versions and offers to install it")
    func downloaded() {
        let prompt = UpdatePrompt(release: release, running: running, isDownloaded: true, canInstall: true, isHomebrewInstall: false)
        #expect(prompt.title == "AutoHush 0.3.8 Is Ready to Install")
        #expect(prompt.message == "You’re running version 0.3.7, and version 0.3.8 is downloaded. Installing it restarts AutoHush.")
        #expect(prompt.buttons.map(\.title) == ["Install and Relaunch", "Later", "Open Release Page"])
        #expect(prompt.buttons.first?.choice == .install)
    }

    @Test("a release candidate says it's a test version of the next release, offered or downloaded; the same buttons")
    func releaseCandidate() {
        let candidate = AppRelease.github("0.3.8-rc.1", diskImage: false)
        let available = UpdatePrompt(release: candidate, running: running, isDownloaded: false, canInstall: true, isHomebrewInstall: false)
        #expect(available.title == "AutoHush 0.3.8 RC 1 Is Available")
        #expect(available.message == "You’re running version 0.3.7, and version 0.3.8 RC 1 is available. It’s a release candidate, a test version of the next release. Installing it restarts AutoHush.")
        #expect(available.buttons.map(\.choice) == [.install, .later, .openReleasePage])
        let downloaded = UpdatePrompt(release: candidate, running: running, isDownloaded: true, canInstall: true, isHomebrewInstall: false)
        #expect(downloaded.message == "You’re running version 0.3.7, and version 0.3.8 RC 1 is downloaded. It’s a release candidate, a test version of the next release. Installing it restarts AutoHush.")
    }

    @Test("the latest release offered back from a release candidate says why; a newer release offered on one is an ordinary update")
    func backFromReleaseCandidate() {
        let candidate = AppVersion("0.3.9-rc.1")!
        for isDownloaded in [false, true] {
            let back = UpdatePrompt(release: release, running: candidate, isDownloaded: isDownloaded, canInstall: true, isHomebrewInstall: false)
            #expect(back.message == "You’re running version 0.3.9 RC 1, a release candidate. Get release candidates is off, so the latest release is offered. Installing it restarts AutoHush.")
        }
        let newer = UpdatePrompt(release: AppRelease.github("0.3.9", diskImage: false), running: candidate, isDownloaded: false,
                                 canInstall: true, isHomebrewInstall: false)
        #expect(newer.message == "You’re running version 0.3.9 RC 1, and version 0.3.9 is available. Installing it restarts AutoHush.")
    }

    @Test("where AutoHush can't update itself, it says how to, with Homebrew or by hand")
    func manual() {
        let homebrew = UpdatePrompt(release: release, running: running, isDownloaded: false, canInstall: false, isHomebrewInstall: true)
        #expect(homebrew.message == "You have version 0.3.7. Update with Homebrew:\n\nbrew upgrade --cask autohush")
        #expect(homebrew.buttons.map(\.choice) == [.openReleasePage, .later])

        let byHand = UpdatePrompt(release: release, running: running, isDownloaded: true, canInstall: false, isHomebrewInstall: false)
        #expect(byHand.title == "AutoHush 0.3.8 Is Available")
        #expect(byHand.message.hasPrefix("You have version 0.3.7. Download it from GitHub"))
        #expect(!byHand.buttons.contains { $0.choice == .install })
    }
}
