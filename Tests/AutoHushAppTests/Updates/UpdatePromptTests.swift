import Foundation
import Testing
@testable import AutoHushApp

@Suite("UpdatePrompt")
struct UpdatePromptTests {
    private let release = AppRelease(
        version: AppVersion("0.3.8")!,
        pageURL: URL(string: "https://github.com/hfustercabre/AutoHush/releases/tag/v0.3.8")!
    )
    private let running = AppVersion("0.3.7")!

    @Test("an update to download says both versions and offers to download and install it")
    func available() {
        let prompt = UpdatePrompt(release: release, running: running, isDownloaded: false, canInstall: true, isHomebrewInstall: false)
        #expect(prompt.title == "AutoHush 0.3.8 Is Available")
        #expect(prompt.message == "You're running version 0.3.7, and version 0.3.8 is available. Installing it restarts AutoHush.")
        #expect(prompt.buttons.map(\.title) == ["Download and Install", "Later", "Open Release Page"])
        #expect(prompt.buttons.map(\.choice) == [.install, .later, .openReleasePage])
    }

    @Test("a downloaded update says both versions and offers to install it")
    func downloaded() {
        let prompt = UpdatePrompt(release: release, running: running, isDownloaded: true, canInstall: true, isHomebrewInstall: false)
        #expect(prompt.title == "AutoHush 0.3.8 Is Ready to Install")
        #expect(prompt.message == "You're running version 0.3.7, and version 0.3.8 is downloaded. Installing it restarts AutoHush.")
        #expect(prompt.buttons.map(\.title) == ["Install and Relaunch", "Later", "Open Release Page"])
        #expect(prompt.buttons.first?.choice == .install)
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

@Suite("UpdateNotice")
struct UpdateNoticeTests {
    private let version = AppVersion("0.3.8")!

    @Test("each notice says what happened, and is told apart by kind and version")
    func texts() {
        let available = UpdateNotice.available(version, running: AppVersion("0.3.7")!)
        #expect(available.title == "AutoHush 0.3.8 is available")
        #expect(available.body == "You're running 0.3.7. Click to see what's new and install it.")
        #expect(available.key == "available 0.3.8")
        #expect(UpdateNotice.downloaded(version).title == "AutoHush 0.3.8 is ready to install")
        #expect(UpdateNotice.downloaded(version).key == "downloaded 0.3.8")
        #expect(UpdateNotice.installed(version).title == "AutoHush was updated to 0.3.8")
        #expect(UpdateNotice.installed(version).body == "Click to see what's new.")
        #expect(UpdateNotice.installFailed(version).title == "Couldn't update AutoHush to 0.3.8")
        #expect(UpdateNotice.installFailed(version).key == "installFailed 0.3.8")
    }
}
