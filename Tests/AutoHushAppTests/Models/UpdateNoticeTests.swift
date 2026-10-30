import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit

@Suite("UpdateNotice")
struct UpdateNoticeTests {
    private let version = AppVersion("0.3.8")!

    @Test("each notice says what happened, and is told apart by kind and version")
    func texts() {
        let available = UpdateNotice.available(version, running: AppVersion("0.3.7")!)
        #expect(available.title == "AutoHush 0.3.8 is available")
        #expect(available.body == "You’re running 0.3.7. Click to see what’s new and install it.")
        #expect(available.key == "available 0.3.8")
        #expect(UpdateNotice.downloaded(version).title == "AutoHush 0.3.8 is ready to install")
        #expect(UpdateNotice.downloaded(version).key == "downloaded 0.3.8")
        #expect(UpdateNotice.installed(version).title == "AutoHush was updated to 0.3.8")
        #expect(UpdateNotice.installed(version).body == "Click to see what’s new.")
        #expect(UpdateNotice.installFailed(version).title == "Couldn’t update AutoHush to 0.3.8")
        #expect(UpdateNotice.installFailed(version).key == "installFailed 0.3.8")
        // Settings' choice that leads to “ready to install” says how long the download is kept.
        #expect(AutomaticUpdates.download.explanation.contains("\(Int(UpdateDownloads.keepFor / 86_400)) days"))
    }
}
