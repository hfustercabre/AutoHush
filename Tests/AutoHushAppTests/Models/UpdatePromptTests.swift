import Foundation
import Testing
@testable import AutoHushApp

@Suite("UpdatePrompt")
struct UpdatePromptTests {
    private let release = AppRelease.github("0.3.8", diskImage: false)
    private let running = AppVersion("0.3.7")!

    @Test("an update to download says the version running and offers to download and install it")
    func available() {
        let prompt = UpdatePrompt(release: release, running: running, isDownloaded: false, canInstall: true, isHomebrewInstall: false)
        #expect(prompt.title == "AutoHush 0.3.8 Is Available")
        #expect(prompt.message == "You have version 0.3.7. Installing it restarts AutoHush.")
        #expect(prompt.buttons.map(\.title) == ["Download and Install", "Later", "Open Release Page"])
        #expect(prompt.buttons.map(\.choice) == [.install, .later, .openReleasePage])
    }

    @Test("a downloaded update says the version running and offers to install it")
    func downloaded() {
        let prompt = UpdatePrompt(release: release, running: running, isDownloaded: true, canInstall: true, isHomebrewInstall: false)
        #expect(prompt.title == "AutoHush 0.3.8 Is Ready to Install")
        #expect(prompt.message == "You have version 0.3.7. Installing it restarts AutoHush.")
        #expect(prompt.buttons.map(\.title) == ["Install and Relaunch", "Later", "Open Release Page"])
        #expect(prompt.buttons.first?.choice == .install)
    }

    @Test("a release candidate says it is one, offered or downloaded; the same buttons")
    func releaseCandidate() {
        let candidate = AppRelease.github("0.3.8-rc.1", diskImage: false)
        let available = UpdatePrompt(release: candidate, running: running, isDownloaded: false, canInstall: true, isHomebrewInstall: false)
        #expect(available.title == "AutoHush 0.3.8 RC 1 Is Available")
        #expect(available.message == "You have version 0.3.7. Installing this release candidate restarts AutoHush.")
        #expect(available.buttons.map(\.choice) == [.install, .later, .openReleasePage])
        let downloaded = UpdatePrompt(release: candidate, running: running, isDownloaded: true, canInstall: true, isHomebrewInstall: false)
        #expect(downloaded.message == "You have version 0.3.7. Installing this release candidate restarts AutoHush.")
    }

    @Test("the latest release offered back from a release candidate says why; a newer release offered on one is an ordinary update")
    func backFromReleaseCandidate() {
        let candidate = AppVersion("0.3.9-rc.1")!
        for isDownloaded in [false, true] {
            let back = UpdatePrompt(release: release, running: candidate, isDownloaded: isDownloaded, canInstall: true, isHomebrewInstall: false)
            #expect(back.message == "You have version 0.3.9 RC 1, and Get release candidates is off. Installing this release restarts AutoHush.")
        }
        let newer = UpdatePrompt(release: AppRelease.github("0.3.9", diskImage: false), running: candidate, isDownloaded: false,
                                 canInstall: true, isHomebrewInstall: false)
        #expect(newer.message == "You have version 0.3.9 RC 1. Installing it restarts AutoHush.")
    }

    @Test("where AutoHush can't update itself, a release candidate says so, by hand also with Homebrew, which has none; the way back says why, with Homebrew a reinstall")
    func manualReleaseCandidate() {
        let candidate = AppRelease.github("0.3.8-rc.1", diskImage: false)
        for homebrew in [false, true] {
            let offered = UpdatePrompt(release: candidate, running: running, isDownloaded: false, canInstall: false, isHomebrewInstall: homebrew)
            #expect(offered.title == "AutoHush 0.3.8 RC 1 Is Available")
            #expect(offered.message == (homebrew
                ? "You have version 0.3.7. Homebrew has no release candidates: download this one from GitHub and replace AutoHush in Applications."
                : "You have version 0.3.7. Download this release candidate from GitHub and replace AutoHush in Applications."))
            #expect(offered.buttons.map(\.choice) == [.openReleasePage, .later])
        }
        let onCandidate = AppVersion("0.3.9-rc.1")!
        let back = UpdatePrompt(release: release, running: onCandidate, isDownloaded: false, canInstall: false, isHomebrewInstall: false)
        #expect(back.message == "You have version 0.3.9 RC 1, and Get release candidates is off. Download this release from GitHub and replace AutoHush in Applications.")
        let backWithHomebrew = UpdatePrompt(release: release, running: onCandidate, isDownloaded: false, canInstall: false, isHomebrewInstall: true)
        #expect(backWithHomebrew.message == "You have version 0.3.9 RC 1, and Get release candidates is off. Go back with Homebrew:\n\nbrew reinstall --cask autohush")
    }

    @Test("where AutoHush can't update itself, it says how to, with Homebrew or by hand")
    func manual() {
        let homebrew = UpdatePrompt(release: release, running: running, isDownloaded: false, canInstall: false, isHomebrewInstall: true)
        #expect(homebrew.message == "You have version 0.3.7. Update with Homebrew:\n\nbrew upgrade --cask autohush")
        #expect(homebrew.buttons.map(\.choice) == [.openReleasePage, .later])

        let byHand = UpdatePrompt(release: release, running: running, isDownloaded: true, canInstall: false, isHomebrewInstall: false)
        #expect(byHand.title == "AutoHush 0.3.8 Is Available")
        #expect(byHand.message == "You have version 0.3.7. Download the new one from GitHub and replace AutoHush in Applications.")
        #expect(!byHand.buttons.contains { $0.choice == .install })
    }
}
